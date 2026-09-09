defmodule Src.Explanation.Verbal.HPCConnect do
  @moduledoc """
  Executes Transformers verbalization jobs on the Iris GPU cluster.

  The adapter stages the existing Python verbalization package, its locked
  environment description, the request and the referenced report. It delegates
  transport and remote commands to `penthooose/hpc_connect`, submits the Python
  launcher through SLURM, and retrieves the generated artifacts afterwards.

  SSH authentication remains outside ModalLens. The user opens an OpenSSH
  ControlMaster for the configured `ssh_alias`; this module only verifies and
  reuses that connection and never reads a private key or passphrase.
  """

  alias HpcConnect.{Cluster, Command, Session, SSH}

  @default_hpc_module HpcConnect
  @default_transfer_module SSH

  @metadata_begin "__MODAL_LENS_SLURM_METADATA_BEGIN__"
  @metadata_end "__MODAL_LENS_SLURM_METADATA_END__"

  @typedoc "SLURM provenance for one remote verbalization job."
  @type provenance :: %{
          required(:role) => :verbalization,
          required(:scheduler) => :slurm,
          required(:ssh_alias) => String.t(),
          required(:remote_dir) => String.t(),
          required(:partition) => String.t(),
          required(:cpus_per_task) => pos_integer(),
          required(:gpus_per_task) => pos_integer(),
          required(:time_limit) => String.t(),
          required(:artifacts) => %{
            required(:stdout) => String.t(),
            required(:stderr) => String.t(),
            required(:output_directory) => String.t()
          },
          optional(:job_id) => String.t(),
          optional(:node) => String.t(),
          optional(:state) => String.t(),
          optional(:exit_code) => String.t(),
          optional(:started_at) => String.t(),
          optional(:ended_at) => String.t()
        }

  @doc """
  Runs one existing Transformers verbalization request as a GPU SLURM job.

  The successful response has the same string-keyed shape as the local Python
  launcher. Its artifact paths refer to the retrieved local files, and the
  additional `"hpc_provenance"` field contains the Iris job metadata.
  """
  @spec run_request(Path.t()) :: {:ok, map()} | {:error, term()}
  @spec run_request(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_request(request_path, opts \\ []) when is_binary(request_path) do
    config = Application.get_env(:modal_lens, :verbalization_hpc, [])
    job = Keyword.merge(Keyword.get(config, :job, []), Keyword.get(opts, :job, []))
    opts = config |> Keyword.merge(opts) |> Keyword.put(:job, job)
    request_path = Path.expand(request_path)

    with {:ok, request} <- read_request(request_path),
         :ok <- validate_request(request, request_path),
         :ok <- validate_options(opts),
         {:ok, staging} <- prepare_staging(request_path, request, opts) do
      try do
        with {:ok, hpc_module, session} <- start_session(opts),
             :ok <- ensure_control_connection(hpc_module, session, opts),
             {:ok, response} <- execute_remote(hpc_module, session, staging, request, opts) do
          {:ok, response}
        end
      after
        cleanup_staging(staging)
      end
    end
  end

  defp execute_remote(hpc_module, session, staging, request, opts) do
    remote_dir = remote_directory(request, opts)
    remote_output_directory = remote_join(remote_dir, "output")
    job = Keyword.fetch!(opts, :job)
    cpus = Keyword.get(job, :cpus_per_task, 4)
    gpus = Keyword.get(job, :gpus, 1)
    time_limit = Keyword.get(job, :time_limit, "00:30:00")
    partition = Keyword.get(job, :partition, "gpu")
    remote_preamble = Keyword.get(opts, :remote_preamble, "")
    uv_executable = Keyword.get(opts, :uv_executable, "uv")

    batch_script = """
    #!/bin/bash --login
    set -e
    #{remote_preamble}
    #{shell_escape(uv_executable)} sync --frozen
    #{shell_escape(uv_executable)} pip install \
      --python .venv/bin/python \
      --reinstall-package torch \
      --index-url https://download.pytorch.org/whl/cu126 \
      'torch==2.13.0'
    exec .venv/bin/python \
      -m verbalization.launcher verbalization_request.json
    """

    prepare_command = """
    set -e
    mkdir -p -- #{shell_escape(Path.dirname(remote_dir))}
    test ! -e #{shell_escape(remote_dir)}
    """

    command = """
    set -e
    cd -- #{shell_escape(remote_dir)}
    printf '%s' #{shell_escape(Base.encode64(batch_script))} | base64 --decode > job.sh
    status=0
    sbatch --parsable --wait --job-name=modal-lens-verbalization \\
      --nodes=1 --ntasks=1 \\
      --partition=#{shell_escape(partition)} \\
      --cpus-per-task=#{shell_escape(cpus)} \\
      --gpus-per-task=#{shell_escape(gpus)} \\
      --time=#{shell_escape(time_limit)} \\
      --chdir="$PWD" --output=slurm.stdout --error=slurm.stderr \\
      --open-mode=truncate job.sh > slurm.submission 2> slurm.submission.stderr || status=$?
    job_id=$(cut -d ';' -f 1 < slurm.submission | tr -d '[:space:]')
    printf '%s\\n' "$status" > slurm.exit_code
    if [ "$status" -ne 0 ]; then
      cat slurm.submission slurm.submission.stderr
    fi
    if [ -f slurm.stdout ]; then cat slurm.stdout; fi
    if [ -f slurm.stderr ]; then cat slurm.stderr; fi
    printf '\\n%s\\n' #{shell_escape(@metadata_begin)}
    printf 'job_id=%s\\n' "$job_id"
    if [ -n "$job_id" ]; then
      scontrol show job "$job_id" -o 2>/dev/null || true
    fi
    printf '%s\\n' #{shell_escape(@metadata_end)}
    if [ "$status" -eq 0 ] && [ ! -d output ]; then
      printf '%s\\n' 'SLURM finished but the verbalization output directory is missing.' >&2
      exit 1
    fi
    exit "$status"
    """

    transfer_module = Keyword.get(opts, :transfer_module, @default_transfer_module)

    transfer_opts =
      opts
      |> Keyword.get(:transfer_opts, [])
      |> Keyword.put(:recursive, true)
      |> Keyword.put(:retries, 0)

    try do
      _output =
        apply(hpc_module, :connect!, [
          session,
          prepare_command,
          connect_opts(hpc_module, opts, 3)
        ])

      :ok =
        apply(transfer_module, :upload!, [
          session,
          staging.source,
          remote_dir,
          transfer_opts
        ])

      output =
        apply(hpc_module, :connect!, [
          session,
          command,
          connect_opts(hpc_module, opts, 0)
        ])

      with :ok <-
             retrieve_output(
               hpc_module,
               remote_output_directory,
               staging.local_output_directory,
               opts
             ),
           {:ok, response} <-
             format_result(
               output,
               staging,
               remote_dir,
               remote_output_directory,
               partition,
               cpus,
               gpus,
               time_limit,
               opts
             ) do
        {:ok, response}
      end
    rescue
      exception ->
        {:error, {:hpc_verbalization_failed, Exception.message(exception)}}
    end
  end

  defp prepare_staging(request_path, request, opts) do
    project_root = opts |> Keyword.get(:project_root, File.cwd!()) |> Path.expand()
    package_directory = Path.join(project_root, "verbalization")
    pyproject_path = Path.join(project_root, "pyproject.toml")
    lock_path = Path.join(project_root, "uv.lock")
    request_directory = Path.dirname(request_path)
    report_path = resolve_local_path(request_directory, request["report_path"])
    output_directory = resolve_local_path(request_directory, request["output_directory"])

    required_paths = [package_directory, pyproject_path, lock_path, report_path]

    case Enum.find(required_paths, &(not File.exists?(&1))) do
      nil ->
        create_staging_tree(
          request_path,
          request,
          package_directory,
          pyproject_path,
          lock_path,
          report_path,
          output_directory
        )

      missing_path ->
        {:error, {:missing_verbalization_staging_input, missing_path}}
    end
  rescue
    exception -> {:error, {:verbalization_staging_failed, Exception.message(exception)}}
  end

  defp create_staging_tree(
         request_path,
         request,
         package_directory,
         pyproject_path,
         lock_path,
         report_path,
         output_directory
       ) do
    cleanup_directory =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_verbalization_hpc_#{System.unique_integer([:positive, :monotonic])}"
      )

    staging_directory = Path.join(cleanup_directory, "staging")
    File.mkdir_p!(staging_directory)

    copy_directory!(package_directory, Path.join(staging_directory, "verbalization"))
    File.cp!(pyproject_path, Path.join(staging_directory, "pyproject.toml"))
    File.cp!(lock_path, Path.join(staging_directory, "uv.lock"))
    File.cp!(report_path, Path.join(staging_directory, "report.json"))

    staged_request =
      request
      |> Map.put("report_path", "report.json")
      |> Map.put("output_directory", "output")

    File.write!(
      Path.join(staging_directory, "verbalization_request.json"),
      Jason.encode!(staged_request, pretty: true) <> "\n"
    )

    {:ok,
     %{
       source: staging_directory,
       cleanup_directory: cleanup_directory,
       local_request_path: request_path,
       local_output_directory: output_directory
     }}
  end

  defp copy_directory!(source, destination) do
    case File.cp_r(source, destination) do
      {:ok, _paths} -> :ok
      {:error, reason, path} -> raise File.Error, reason: reason, action: "copy", path: path
    end
  end

  defp retrieve_output(hpc_module, remote_output_directory, local_output_directory, opts) do
    File.mkdir_p!(local_output_directory)

    case Keyword.get(opts, :download_fun) do
      download_fun when is_function(download_fun, 2) ->
        download_fun.(remote_output_directory, local_output_directory)

      _other ->
        ssh_alias = Keyword.get(opts, :ssh_alias, "iris-cluster")

        command = %Command{
          binary: SSH.scp_binary(),
          args: [
            "-r",
            "-o",
            "BatchMode=yes",
            "-o",
            "PasswordAuthentication=no",
            "-o",
            "NumberOfPasswordPrompts=0",
            "-o",
            "ConnectTimeout=30",
            "#{ssh_alias}:#{remote_output_directory}/.",
            local_output_directory
          ],
          summary: "Retrieve Iris verbalization artifacts",
          remote_command: nil
        }

        case apply(hpc_module, :run_command, [command, [retries: 0]]) do
          {_output, 0} -> :ok
          {output, status} -> {:error, {:hpc_artifact_retrieval_failed, status, output}}
        end
    end
  end

  defp format_result(
         output,
         staging,
         remote_dir,
         remote_output_directory,
         partition,
         cpus,
         gpus,
         time_limit,
         opts
       ) do
    {launcher_output, dynamic_metadata} = split_remote_output(output)

    provenance =
      %{
        role: :verbalization,
        scheduler: :slurm,
        ssh_alias: Keyword.get(opts, :ssh_alias, "iris-cluster"),
        remote_dir: remote_dir,
        partition: partition,
        cpus_per_task: cpus,
        gpus_per_task: gpus,
        time_limit: time_limit,
        artifacts: %{
          stdout: remote_join(remote_dir, "slurm.stdout"),
          stderr: remote_join(remote_dir, "slurm.stderr"),
          output_directory: remote_output_directory
        }
      }
      |> Map.merge(dynamic_metadata)

    with {:ok, response} <- decode_response(launcher_output) do
      response =
        response
        |> localize_response(staging)
        |> Map.put("hpc_provenance", provenance)

      {:ok, response}
    end
  end

  defp localize_response(response, staging) do
    artifacts =
      case response["artifacts"] do
        %{} = paths ->
          Map.new(paths, fn
            {name, path} when is_binary(path) ->
              {name, Path.join(staging.local_output_directory, Path.basename(path))}

            entry ->
              entry
          end)

        _other ->
          %{}
      end

    response
    |> Map.put("request_path", staging.local_request_path)
    |> Map.put("artifacts", artifacts)
  end

  defp decode_response(output) do
    response =
      output
      |> String.split("\n", trim: true)
      |> Enum.reverse()
      |> Enum.find_value(fn line ->
        case Jason.decode(line) do
          {:ok, %{} = decoded} -> decoded
          _other -> nil
        end
      end)

    case response do
      nil ->
        {:error, {:invalid_remote_verbalization_response, output}}

      %{"status" => "completed"} = decoded ->
        {:ok, decoded}

      decoded ->
        {:error, {:remote_verbalization_failed, decoded}}
    end
  end

  defp split_remote_output(output) do
    case String.split(output, @metadata_begin, parts: 2) do
      [launcher_output, metadata_and_suffix] ->
        case String.split(metadata_and_suffix, @metadata_end, parts: 2) do
          [metadata, _suffix] ->
            {String.trim_trailing(launcher_output, "\n"), parse_slurm_metadata(metadata)}

          _other ->
            {output, %{}}
        end

      _other ->
        {output, %{}}
    end
  end

  defp parse_slurm_metadata(metadata) do
    %{
      job_id: metadata_field(metadata, "job_id") || metadata_field(metadata, "JobId"),
      node: metadata_field(metadata, "NodeList"),
      state: metadata_field(metadata, "JobState"),
      exit_code: metadata_field(metadata, "ExitCode"),
      started_at: metadata_field(metadata, "StartTime"),
      ended_at: metadata_field(metadata, "EndTime")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", "Unknown", "None"] end)
    |> Map.new()
  end

  defp metadata_field(metadata, key) do
    pattern = Regex.compile!("(?:^|\\s)#{Regex.escape(key)}=(\\S+)")

    case Regex.run(pattern, metadata, capture: :all_but_first) do
      [value] -> value
      _other -> nil
    end
  end

  defp validate_request(
         %{
           "backend" => "transformers",
           "report_path" => report_path,
           "output_directory" => output_directory
         },
         _request_path
       )
       when is_binary(report_path) and report_path != "" and is_binary(output_directory) and
              output_directory != "" do
    :ok
  end

  defp validate_request(%{"backend" => backend}, _request_path) when backend != "transformers" do
    {:error, {:unsupported_hpc_verbalization_backend, backend}}
  end

  defp validate_request(_request, request_path) do
    {:error, {:invalid_verbalization_request, request_path}}
  end

  defp validate_options(opts) do
    job = Keyword.fetch!(opts, :job)
    scheduler = Keyword.get(opts, :scheduler, :slurm)
    cpus = Keyword.get(job, :cpus_per_task, 4)
    gpus = Keyword.get(job, :gpus, 1)
    time_limit = Keyword.get(job, :time_limit, "00:30:00")
    partition = Keyword.get(job, :partition, "gpu")
    ssh_alias = Keyword.get(opts, :ssh_alias, "iris-cluster")

    cond do
      scheduler != :slurm ->
        {:error, {:unsupported_hpc_scheduler, scheduler}}

      not (is_integer(cpus) and cpus > 0) ->
        {:error, {:invalid_hpc_option, :cpus_per_task, cpus}}

      not (is_integer(gpus) and gpus > 0) ->
        {:error, {:invalid_hpc_option, :gpus, gpus}}

      not (is_binary(time_limit) and time_limit != "") ->
        {:error, {:invalid_hpc_option, :time_limit, time_limit}}

      not (is_binary(partition) and partition != "") ->
        {:error, {:invalid_hpc_option, :partition, partition}}

      not (is_binary(ssh_alias) and ssh_alias != "") ->
        {:error, {:invalid_hpc_option, :ssh_alias, ssh_alias}}

      true ->
        :ok
    end
  end

  defp read_request(path) do
    with {:ok, source} <- File.read(path),
         {:ok, %{} = request} <- Jason.decode(source) do
      {:ok, request}
    else
      {:ok, _other} ->
        {:error, {:invalid_verbalization_request, path}}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_verbalization_request_json, path, Exception.message(error)}}

      {:error, reason} ->
        {:error, {:cannot_read_verbalization_request, path, reason}}
    end
  end

  defp resolve_local_path(base_directory, path) do
    Path.expand(path, base_directory)
  end

  defp cleanup_staging(%{cleanup_directory: cleanup_directory}) do
    File.rm_rf(cleanup_directory)
    :ok
  end

  defp ensure_control_connection(hpc_module, %Session{} = session, opts) do
    ssh_alias = Keyword.get(opts, :ssh_alias, session.ssh_alias)

    command = %Command{
      binary: SSH.ssh_binary(),
      args: ["-O", "check", ssh_alias],
      summary: "Check authenticated Iris SSH ControlMaster",
      remote_command: nil
    }

    try do
      case apply(hpc_module, :run_command, [command, [retries: 0]]) do
        {_output, 0} -> :ok
        {output, status} -> control_connection_error(ssh_alias, status, output)
      end
    rescue
      exception -> control_connection_error(ssh_alias, nil, Exception.message(exception))
    end
  end

  defp ensure_control_connection(_hpc_module, _session, _opts), do: :ok

  defp control_connection_error(ssh_alias, status, output) do
    {:error,
     {:ssh_control_connection_required,
      %{
        ssh_alias: ssh_alias,
        exit_code: status,
        output: String.trim(to_string(output)),
        command: "ssh -o BatchMode=no -MNf #{shell_escape(ssh_alias)}"
      }}}
  end

  defp start_session(opts) do
    hpc_module = Keyword.get(opts, :hpc_module, @default_hpc_module)

    if Code.ensure_loaded?(hpc_module) do
      try do
        work_dir = Keyword.get(opts, :hpc_work_dir, "modal_lens_runtime")
        vault_dir = Keyword.get(opts, :vault_dir, "modal_lens_vault")

        cluster = %Cluster{
          name: :iris,
          host: "access-iris.uni.lu",
          ssh_alias: "iris-cluster",
          aliases: ["iris", "iris-cluster", "access-iris.uni.lu"],
          default_work_dir: work_dir,
          vault_dir: vault_dir,
          default_partition: "gpu",
          gpu_type: "v100",
          notes: "University of Luxembourg Iris GPU cluster"
        }

        session_opts = [
          ssh_alias: Keyword.get(opts, :ssh_alias, cluster.ssh_alias),
          username: nil,
          identity_file: nil,
          proxy_jump: nil,
          work_dir: work_dir,
          vault_dir: vault_dir
        ]

        {:ok, hpc_module, apply(hpc_module, :new_session, [cluster, session_opts])}
      rescue
        exception -> {:error, {:hpc_bootstrap_failed, Exception.message(exception)}}
      end
    else
      {:error, {:hpc_connect_not_available, hpc_module}}
    end
  end

  defp connect_opts(hpc_module, opts, retries) do
    opts
    |> Keyword.get(:connect_opts, [])
    |> Keyword.put(:run_fun, fn command, run_opts ->
      command = %{command | args: ["-T", "-n", "-o", "BatchMode=yes" | command.args]}

      apply(hpc_module, :run_command!, [command, Keyword.put(run_opts, :retries, retries)])
    end)
  end

  defp remote_directory(request, opts) do
    case Keyword.get(opts, :remote_dir) do
      path when is_binary(path) and path != "" ->
        String.trim_trailing(path, "/")

      _other ->
        base_directory =
          opts
          |> Keyword.get(:remote_base_dir, "modal_lens_verbalization")
          |> String.trim_trailing("/")

        path_component =
          request
          |> Map.get("model_id", "transformers")
          |> to_string()
          |> String.replace(~r/[^a-zA-Z0-9_.-]/, "_")

        suffix = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
        base_directory <> "/" <> path_component <> "-" <> suffix
    end
  end

  defp remote_join(base, relative_path) do
    String.trim_trailing(base, "/") <> "/" <> String.trim_leading(relative_path, "/")
  end

  defp shell_escape(value) do
    escaped = value |> to_string() |> String.replace("'", "'\"'\"'")
    "'" <> escaped <> "'"
  end
end
