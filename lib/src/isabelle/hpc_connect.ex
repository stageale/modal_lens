defmodule Src.Isabelle.HPCConnect do
  @moduledoc """
  Remote Isabelle backend using the external `penthooose/hpc_connect` library.

  This module is intentionally thin:

    * it does not generate HOL itself;
    * it assumes `ROOT` and `<Theory>.thy` already exist in `workdir`;
    * it uses HpcConnect for session creation, staging and remote execution;
    * it returns the same shape as the local backend: `{:ok, log}` or `{:error, reason}`.

  Configuration is read from `:modal_lens, :isabelle_hpc`.
  SSH authentication is managed by a user-started OpenSSH ControlMaster.
  ModalLens never reads a private key or passphrase and never starts the
  authenticated connection itself.
  """

  alias HpcConnect.{Cluster, Command, Session, SSH}

  @default_hpc_module HpcConnect
  @default_transfer_module SSH

  @metadata_begin "__MODAL_LENS_SLURM_METADATA_BEGIN__"
  @metadata_end "__MODAL_LENS_SLURM_METADATA_END__"

  @type hpc_spec :: %{required(:theory_name) => String.t()}

  @typedoc "SLURM and remote-execution provenance returned by the HPC backend."
  @type provenance :: %{
          required(:role) => :isabelle,
          required(:scheduler) => :slurm,
          required(:ssh_alias) => String.t(),
          required(:remote_dir) => String.t(),
          required(:cpus_per_task) => pos_integer(),
          required(:time_limit) => String.t(),
          required(:artifacts) => %{
            required(:stdout) => String.t(),
            required(:stderr) => String.t()
          },
          optional(:job_id) => String.t(),
          optional(:node) => String.t(),
          optional(:state) => String.t(),
          optional(:exit_code) => String.t(),
          optional(:started_at) => String.t(),
          optional(:ended_at) => String.t()
        }

  @typedoc "Isabelle log together with its HPC provenance."
  @type result :: %{
          required(:log) => String.t(),
          required(:provenance) => provenance()
        }

  @doc """
  Executes an existing Isabelle session on the configured HPC system.

  By default, the function preserves the local-backend-compatible return value
  `{:ok, log}`. With `return_metadata?: true`, it returns
  `{:ok, %{log: log, provenance: provenance}}` instead.

  Before staging, the function verifies that the user has already opened the
  configured OpenSSH ControlMaster connection. If it is missing, the returned
  error contains the external command that the user must run in a terminal.
  """
  @spec run(String.t(), hpc_spec()) :: {:ok, String.t() | result()} | {:error, term()}
  @spec run(String.t(), hpc_spec(), keyword()) :: {:ok, String.t() | result()} | {:error, term()}
  def run(workdir, %{theory_name: theory_name}, opts \\ [])
      when is_binary(workdir) and is_binary(theory_name) do
    config = Application.get_env(:modal_lens, :isabelle_hpc, [])
    job = Keyword.merge(Keyword.get(config, :job, []), Keyword.get(opts, :job, []))
    opts = config |> Keyword.merge(opts) |> Keyword.put(:job, job)

    workdir = Path.expand(workdir)

    root_path = Path.join(workdir, "ROOT")

    theory_path = Path.join(workdir, "#{theory_name}.thy")

    with {:ok, _root_text} <- read_required_file(root_path),
         {:ok, _theory_text} <- read_required_file(theory_path),
         :ok <- validate_options(opts),
         {:ok, hpc_module, session} <- start_session(opts),
         :ok <- ensure_control_connection(hpc_module, session, opts),
         {:ok, log} <-
           execute_remote(hpc_module, session, workdir, theory_name, opts) do
      {:ok, log}
    end
  end

  defp ensure_control_connection(hpc_module, %Session{} = session, opts) do
    ssh_alias =
      Keyword.get(opts, :ssh_alias, session.ssh_alias)

    command = %Command{
      binary: SSH.ssh_binary(),
      args: ["-O", "check", ssh_alias],
      summary: "Check authenticated SSH ControlMaster",
      remote_command: nil
    }

    try do
      case apply(hpc_module, :run_command, [command, [retries: 0]]) do
        {_output, 0} ->
          :ok

        {output, exit_code} ->
          control_connection_error(ssh_alias, exit_code, output)
      end
    rescue
      exception ->
        control_connection_error(ssh_alias, nil, Exception.message(exception))
    end
  end

  # Injected test backends may use a lightweight session value instead of the
  # HpcConnect.Session struct and therefore do not perform an external check.
  defp ensure_control_connection(_hpc_module, _session, _opts),
    do: :ok

  defp control_connection_error(ssh_alias, exit_code, output) do
    {:error,
     {:ssh_control_connection_required,
      %{
        ssh_alias: ssh_alias,
        exit_code: exit_code,
        output: String.trim(to_string(output)),
        command: "ssh -o BatchMode=no -MNf #{shell_escape(ssh_alias)}"
      }}}
  end

  defp validate_options(opts) do
    job = Keyword.fetch!(opts, :job)
    scheduler = Keyword.get(opts, :scheduler, :slurm)
    cpus = Keyword.get(job, :cpus_per_task, 8)
    time_limit = Keyword.get(job, :time_limit, "00:30:00")
    ssh_alias = Keyword.get(opts, :ssh_alias, "aion-cluster")

    cond do
      scheduler != :slurm ->
        {:error, {:unsupported_hpc_scheduler, scheduler}}

      not (is_integer(cpus) and cpus > 0) ->
        {:error, {:invalid_hpc_option, :cpus_per_task, cpus}}

      not (is_binary(time_limit) and time_limit != "") ->
        {:error, {:invalid_hpc_option, :time_limit, time_limit}}

      not (is_binary(ssh_alias) and ssh_alias != "") ->
        {:error, {:invalid_hpc_option, :ssh_alias, ssh_alias}}

      true ->
        :ok
    end
  end

  defp execute_remote(hpc_module, session, workdir, theory_name, opts) do
    case prepare_staging(workdir, opts) do
      {:ok, staging} ->
        try do
          execute_staged_remote(
            hpc_module,
            session,
            workdir,
            theory_name,
            opts,
            staging
          )
        after
          cleanup_staging(staging)
        end

      {:error, reason} ->
        {:error, {:hpc_staging_failed, reason}}
    end
  end

  defp execute_staged_remote(hpc_module, session, workdir, theory_name, opts, staging) do
    remote_root = remote_directory(theory_name, opts)
    remote_dir = remote_join(remote_root, staging.relative_workdir)

    isabelle_bin = Keyword.get(opts, :isabelle_bin, "isabelle")
    logic = Keyword.get(opts, :logic, "HOL")
    job = Keyword.fetch!(opts, :job)
    cpus = Keyword.get(job, :cpus_per_task, 8)
    time_limit = Keyword.get(job, :time_limit, "00:30:00")
    remote_preamble = Keyword.get(opts, :remote_preamble, "")

    theory_args =
      workdir
      |> process_theory_paths(theory_name, opts)
      |> Enum.map_join(" \\\n  ", fn path ->
        "-f " <> shell_escape(path)
      end)

    batch_script = """
    #!/bin/bash
    set -e
    #{remote_preamble}
    exec #{shell_escape(isabelle_bin)} process_theories \\
      -O -U \\
      -l #{shell_escape(logic)} \\
      -o #{shell_escape("system_heaps=false")} \\
      -o #{shell_escape("threads=#{cpus}")} \\
      #{theory_args}
    """

    prepare_command = """
    set -e
    mkdir -p -- #{shell_escape(Path.dirname(remote_root))}
    test ! -e #{shell_escape(remote_root)}
    """

    command = """
    set -e
    cd -- #{shell_escape(remote_dir)}
    printf '%s' #{shell_escape(Base.encode64(batch_script))} | base64 --decode > job.sh
    status=0
    sbatch --parsable --wait --nodes=1 --ntasks=1 \\
      --cpus-per-task=#{shell_escape(cpus)} \\
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
    if [ "$status" -eq 0 ] && { [ ! -f slurm.stdout ] || [ ! -f slurm.stderr ]; }; then
      printf '%s\\n' 'SLURM finished but job output files are missing.' >&2
      exit 1
    fi
    exit "$status"
    """

    transfer_module =
      Keyword.get(opts, :transfer_module, @default_transfer_module)

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
          remote_root,
          transfer_opts
        ])

      case apply(hpc_module, :connect!, [
             session,
             command,
             connect_opts(hpc_module, opts, 0)
           ]) do
        output when is_binary(output) ->
          format_result(output, remote_dir, cpus, time_limit, opts)

        output ->
          {:error, {:unexpected_hpc_output, output}}
      end
    rescue
      exception ->
        {:error, {:hpc_execution_failed, Exception.message(exception)}}
    end
  end

  defp process_theory_paths(workdir, theory_name, opts) do
    base_theory_file = Keyword.get(opts, :base_theory_file)

    theory_path =
      Keyword.get(
        opts,
        :theory_path,
        Path.join(workdir, "#{theory_name}.thy")
      )

    (local_import_files(base_theory_file) ++
       [base_theory_file, theory_path])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
    |> Enum.map(&relative_path_from(&1, workdir))
  end

  defp local_import_files(nil), do: []

  defp local_import_files(theory_path) do
    with {:ok, source} <- File.read(theory_path),
         [imports] <-
           Regex.run(
             ~r/\bimports\s+(.*?)\bbegin\b/s,
             source,
             capture: :all_but_first
           ) do
      imports
      |> String.replace(~r/\(\*.*?\*\)/s, " ")
      |> String.replace("\"", "")
      |> String.split()
      |> Enum.map(fn import_name ->
        filename =
          if Path.extname(import_name) == ".thy" do
            import_name
          else
            import_name <> ".thy"
          end

        Path.expand(filename, Path.dirname(theory_path))
      end)
      |> Enum.filter(&File.regular?/1)
    else
      _other -> []
    end
  end

  defp relative_path_from(path, directory) do
    {path_parts, directory_parts} =
      drop_common_prefix(
        Path.split(Path.expand(path)),
        Path.split(Path.expand(directory))
      )

    relative_parts =
      List.duplicate("..", length(directory_parts)) ++ path_parts

    case relative_parts do
      [] -> "."
      parts -> Path.join(parts)
    end
  end

  defp drop_common_prefix(
         [part | path_parts],
         [part | directory_parts]
       ) do
    drop_common_prefix(path_parts, directory_parts)
  end

  defp drop_common_prefix(path_parts, directory_parts) do
    {path_parts, directory_parts}
  end

  defp prepare_staging(workdir, opts) do
    case Keyword.get(opts, :base_theory_file) do
      base_theory_file when is_binary(base_theory_file) and base_theory_file != "" ->
        base_theory_file = Path.expand(base_theory_file)

        if path_within?(base_theory_file, workdir) do
          {:ok, %{source: workdir, relative_workdir: ".", cleanup_dir: nil}}
        else
          prepare_staging_tree(workdir, Path.dirname(base_theory_file))
        end

      _other ->
        {:ok, %{source: workdir, relative_workdir: ".", cleanup_dir: nil}}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp prepare_staging_tree(workdir, base_theory_dir) do
    common_root = common_ancestor(workdir, base_theory_dir)
    relative_workdir = Path.relative_to(workdir, common_root)
    relative_base_dir = Path.relative_to(base_theory_dir, common_root)

    cleanup_dir =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_hpc_staging_#{System.unique_integer([:positive, :monotonic])}"
      )

    staging_root = Path.join(cleanup_dir, "staging")
    staging_workspace = Path.join(staging_root, "workspace")
    File.mkdir_p!(staging_workspace)

    copy_directory!(
      base_theory_dir,
      local_join(staging_workspace, relative_base_dir)
    )

    unless path_within?(workdir, base_theory_dir) do
      copy_directory!(
        workdir,
        local_join(staging_workspace, relative_workdir)
      )
    end

    {:ok,
     %{
       source: staging_root,
       relative_workdir: Path.join("workspace", relative_workdir),
       cleanup_dir: cleanup_dir
     }}
  end

  defp copy_directory!(source, destination) do
    File.mkdir_p!(Path.dirname(destination))

    case File.cp_r(source, destination) do
      {:ok, _paths} ->
        :ok

      {:error, reason, path} ->
        raise File.Error,
          reason: reason,
          action: "copy",
          path: path
    end
  end

  defp cleanup_staging(%{cleanup_dir: nil}), do: :ok

  defp cleanup_staging(%{cleanup_dir: cleanup_dir}) do
    File.rm_rf(cleanup_dir)
    :ok
  end

  defp common_ancestor(left, right) do
    common_parts =
      left
      |> Path.expand()
      |> Path.split()
      |> Enum.zip(right |> Path.expand() |> Path.split())
      |> Enum.take_while(fn {left_part, right_part} ->
        left_part == right_part
      end)
      |> Enum.map(&elem(&1, 0))

    case common_parts do
      [] ->
        raise ArgumentError,
              "workdir and base theory do not share a filesystem root"

      parts ->
        Path.join(parts)
    end
  end

  defp path_within?(path, directory) do
    path_parts =
      path
      |> Path.expand()
      |> Path.split()

    directory_parts =
      directory
      |> Path.expand()
      |> Path.split()

    Enum.take(path_parts, length(directory_parts)) == directory_parts
  end

  defp local_join(base, "."), do: base
  defp local_join(base, relative_path), do: Path.join(base, relative_path)

  defp remote_join(base, "."), do: base

  defp remote_join(base, relative_path) do
    base <> "/" <> String.replace(relative_path, "\\", "/")
  end

  defp format_result(output, remote_dir, cpus, time_limit, opts) do
    {log, dynamic_metadata} = split_remote_output(output)

    provenance =
      %{
        role: :isabelle,
        scheduler: :slurm,
        ssh_alias: Keyword.get(opts, :ssh_alias, "aion-cluster"),
        remote_dir: remote_dir,
        cpus_per_task: cpus,
        time_limit: time_limit,
        artifacts: %{
          stdout: remote_dir <> "/slurm.stdout",
          stderr: remote_dir <> "/slurm.stderr"
        }
      }
      |> Map.merge(dynamic_metadata)

    if Keyword.get(opts, :return_metadata?, false) do
      {:ok, %{log: log, provenance: provenance}}
    else
      {:ok, log}
    end
  end

  defp split_remote_output(output) do
    case String.split(output, @metadata_begin, parts: 2) do
      [log, metadata_and_suffix] ->
        case String.split(metadata_and_suffix, @metadata_end, parts: 2) do
          [metadata, _suffix] ->
            {String.trim_trailing(log, "\n"), parse_slurm_metadata(metadata)}

          _other ->
            {output, %{}}
        end

      _other ->
        {output, %{}}
    end
  end

  defp parse_slurm_metadata(metadata) do
    %{
      job_id:
        metadata_field(metadata, "job_id") ||
          metadata_field(metadata, "JobId"),
      node: metadata_field(metadata, "NodeList"),
      state: metadata_field(metadata, "JobState"),
      exit_code: metadata_field(metadata, "ExitCode"),
      started_at: metadata_field(metadata, "StartTime"),
      ended_at: metadata_field(metadata, "EndTime")
    }
    |> Enum.reject(fn {_key, value} ->
      value in [nil, "", "Unknown", "None"]
    end)
    |> Map.new()
  end

  defp metadata_field(metadata, key) do
    pattern = Regex.compile!("(?:^|\\s)#{Regex.escape(key)}=(\\S+)")

    case Regex.run(pattern, metadata, capture: :all_but_first) do
      [value] -> value
      _other -> nil
    end
  end

  defp connect_opts(hpc_module, opts, retries) do
    opts
    |> Keyword.get(:connect_opts, [])
    |> Keyword.put(:run_fun, fn command, run_opts ->
      command = %{
        command
        | args: ["-T", "-n", "-o", "BatchMode=yes" | command.args]
      }

      apply(hpc_module, :run_command!, [
        command,
        Keyword.put(run_opts, :retries, retries)
      ])
    end)
  end

  defp remote_directory(theory_name, opts) do
    case Keyword.get(opts, :remote_dir) do
      path when is_binary(path) and path != "" ->
        String.trim_trailing(path, "/")

      _other ->
        base_directory =
          opts
          |> Keyword.get(:remote_base_dir, "modal_lens_runs")
          |> String.trim_trailing("/")

        path_component =
          opts
          |> Keyword.get(:run_id, theory_name)
          |> to_string()
          |> String.replace(~r/[^a-zA-Z0-9_.-]/, "_")

        suffix = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
        base_directory <> "/" <> path_component <> "-" <> suffix
    end
  end

  defp shell_escape(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("'", "'\"'\"'")

    "'" <> escaped <> "'"
  end

  defp start_session(opts) do
    hpc_module = Keyword.get(opts, :hpc_module, @default_hpc_module)

    if Code.ensure_loaded?(hpc_module) do
      try do
        cluster =
          opts
          |> Keyword.get(:cluster, :aion)
          |> ulhpc_cluster()

        work_dir = Keyword.get(opts, :hpc_work_dir, "modal_lens_runtime")
        vault_dir = Keyword.get(opts, :vault_dir, "modal_lens_vault")
        cluster = %{cluster | default_work_dir: work_dir, vault_dir: vault_dir}

        session_opts = [
          ssh_alias: Keyword.get(opts, :ssh_alias, cluster.ssh_alias),
          username: nil,
          identity_file: nil,
          proxy_jump: nil,
          work_dir: work_dir,
          vault_dir: vault_dir
        ]

        session = apply(hpc_module, :new_session, [cluster, session_opts])

        {:ok, hpc_module, session}
      rescue
        exception ->
          {:error, {:hpc_bootstrap_failed, Exception.message(exception)}}
      end
    else
      {:error, {:hpc_connect_not_available, hpc_module}}
    end
  end

  defp ulhpc_cluster(cluster) when cluster in [:aion, "aion", "aion-cluster"] do
    %Cluster{
      name: :aion,
      host: "access-aion.uni.lu",
      ssh_alias: "aion-cluster",
      aliases: [
        "aion",
        "aion-cluster",
        "access-aion.uni.lu"
      ],
      notes: "University of Luxembourg Aion cluster"
    }
  end

  defp ulhpc_cluster(cluster) when cluster in [:iris, "iris", "iris-cluster"] do
    %Cluster{
      name: :iris,
      host: "access-iris.uni.lu",
      ssh_alias: "iris-cluster",
      aliases: [
        "iris",
        "iris-cluster",
        "access-iris.uni.lu"
      ],
      notes: "University of Luxembourg Iris cluster"
    }
  end

  defp ulhpc_cluster(cluster) do
    raise ArgumentError, "unsupported ULHPC cluster: #{inspect(cluster)}"
  end

  defp read_required_file(path) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, reason} -> {:error, {:cannot_read_isabelle_file, path, reason}}
    end
  end
end
