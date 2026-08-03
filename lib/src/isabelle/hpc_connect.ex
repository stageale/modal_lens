defmodule Src.Isabelle.HPCConnect do
  @moduledoc """
  Remote Isabelle backend using the external `penthooose/hpc_connect` library.

  This module is intentionally thin:

    * it does not generate HOL itself;
    * it assumes `ROOT` and `<Theory>.thy` already exist in `workdir`;
    * it uses HpcConnect only for session/bootstrap and remote commands;
    * it returns the same shape as the local backend: `{:ok, log}` or `{:error, reason}`.

  The actual external module is injected via `:hpc_module`.
  In production this is `HpcConnect`.
  In tests this can be a fake module.
  """

  alias HpcConnect.Cluster

  @default_hpc_module HpcConnect

  @type hpc_spec :: %{required(:theory_name) => String.t()}

  @doc """
  Executes an existing Isabelle session on the configured HPC system.
  """
  @spec run(String.t(), hpc_spec(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(workdir, %{theory_name: theory_name}, opts \\ [])
      when is_binary(workdir) and is_binary(theory_name) do
    opts =
      :axiom_refiner
      |> Application.get_env(__MODULE__, [])
      |> Keyword.merge(opts)

    workdir = Path.expand(workdir)

    root_path = Path.join(workdir, "ROOT")

    theory_path = Path.join(workdir, "#{theory_name}.thy")

    with {:ok, root_text} <- read_required_file(root_path),
         {:ok, theory_text} <- read_required_file(theory_path),
         {:ok, hpc_module, session} <- start_session(opts),
         {:ok, log} <-
           execute_remote(
             hpc_module,
             session,
             root_text,
             theory_name,
             theory_text,
             opts
           ) do
      {:ok, log}
    end
  end

  defp execute_remote(hpc_module, session, root_text, theory_name, theory_text, opts) do
    remote_dir = remote_directory(theory_name, opts)

    root_path = remote_dir <> "/ROOT"

    theory_path = remote_dir <> "/" <> theory_name <> ".thy"

    session_name = Keyword.get(opts, :session_name, theory_name)

    isabelle_bin = Keyword.get(opts, :isabelle_bin, "isabelle")

    threads = Keyword.get(opts, :threads, 8)

    remote_preamble = Keyword.get(opts, :remote_preamble, "")

    root_base64 = Base.encode64(root_text)

    theory_base64 = Base.encode64(theory_text)

    command = """
    set -e
    mkdir -p #{shell_escape(remote_dir)}
    printf '%s' #{shell_escape(root_base64)} | base64 --decode > #{shell_escape(root_path)}
    printf '%s' #{shell_escape(theory_base64)} | base64 --decode > #{shell_escape(theory_path)}
    cd #{shell_escape(remote_dir)}
    #{remote_preamble}
    #{shell_escape(isabelle_bin)} build \
      -D . \
      -o #{shell_escape("threads=#{threads}")} \
      #{shell_escape(session_name)} 2>&1
    """

    connect_opts = Keyword.get(opts, :connect_opts, [])

    try do
      case apply(hpc_module, :connect!, [session, command, connect_opts]) do
        output when is_binary(output) -> {:ok, output}
        output -> {:error, {:unexpected_hpc_output, output}}
      end
    rescue
      exception ->
        {:error, {:hpc_execution_failed, Exception.message(exception)}}
    end
  end

  defp remote_directory(theory_name, opts) do
    case Keyword.get(opts, :remote_dir) do
      path when is_binary(path) and path != "" ->
        String.trim_trailing(path, "/")

      _other ->
        base_directory =
          opts
          |> Keyword.get(:remote_base_dir, "axiom_refiner_runs")
          |> String.trim_trailing("/")

        run_id =
          Keyword.get(opts, :run_id, theory_name)

        path_component =
          run_id
          |> to_string()
          |> String.replace(~r/[^a-zA-Z0-9_.-]/, "_")

        base_directory <> "/" <> path_component
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

        identity_file =
          case Keyword.get(opts, :key_path) do
            path when is_binary(path) -> Path.expand(path)
            _other -> nil
          end

        session_opts =
          [
            username: Keyword.get(opts, :username),
            ssh_alias: Keyword.get(opts, :ssh_alias, cluster.ssh_alias),
            identity_file: identity_file,
            proxy_jump: Keyword.get(opts, :proxy_jump),
            work_dir: Keyword.get(opts, :hpc_work_dir, "axiom_refiner_runtime"),
            vault_dir: Keyword.get(opts, :vault_dir, "axiom_refiner_vault"),
            port_range: Keyword.get(opts, :port_range),
            env_file: Keyword.get(opts, :env_file)
          ]
          |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

        session =
          apply(hpc_module, :new_session, [cluster, session_opts])

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
