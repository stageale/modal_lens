defmodule Src.Interface.Isabelle.HPCConnect do
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

  @default_hpc_module HpcConnect

  def run(workdir, spec, opts \\ []) do
    hpc_module = Keyword.get(opts, :hpc_module, @default_hpc_module)

    with :ok <- ensure_hpc_module_available(hpc_module),
         {:ok, boot} <- bootstrap(hpc_module, opts),
         {:ok, session} <- fetch_session(boot),
         {:ok, root_text} <- read_required_file(Path.join(workdir, "ROOT")),
         {:ok, thy_text} <- read_required_file(Path.join(workdir, "#{spec.theory_name}.thy")),
         remote_dir <- remote_dir(spec, opts),
         :ok <- ensure_remote_dir(hpc_module, session, remote_dir, opts),
         :ok <- upload_text(hpc_module, session, remote_dir, "ROOT", root_text, opts),
         :ok <-
           upload_text(hpc_module, session, remote_dir, "#{spec.theory_name}.thy", thy_text, opts),
         {:ok, log} <- run_remote_isabelle(hpc_module, session, remote_dir, spec, opts) do
      {:ok, log}
    end
  end

  defp ensure_hpc_module_available(hpc_module) do
    case Code.ensure_loaded?(hpc_module) do
      true ->
        :ok

      false ->
        {:error,
         {:hpc_connect_not_available,
          """
          The module #{inspect(hpc_module)} is not available.

          Either add the dependency later:

              {:hpc_connect, github: "penthooose/hpc_connect"}

          or inject a test module via:

              hpc_module: MyFakeHpcConnect
          """}}
    end
  end

  defp bootstrap(hpc_module, opts) do
    bootstrap_opts =
      [
        mode: Keyword.get(opts, :mode, :local),
        cluster: Keyword.get(opts, :cluster, :alex),
        remote_command: Keyword.get(opts, :remote_command, "hostname && whoami"),

        # For Isabelle we do not need the vLLM/Apptainer helper setup.
        # This keeps bootstrap lightweight.
        install_scripts: Keyword.get(opts, :install_scripts, false),
        install_def_files: Keyword.get(opts, :install_def_files, false)
      ]
      |> put_if_present(:username, Keyword.get(opts, :username))
      |> put_if_present(:key_path, expand_path(Keyword.get(opts, :key_path)))
      |> put_if_present(:env_file, Keyword.get(opts, :env_file))
      |> put_if_present(:ssh_alias, Keyword.get(opts, :ssh_alias))
      |> put_if_present(:proxy_jump, Keyword.get(opts, :proxy_jump))
      |> put_if_present(:work_dir, Keyword.get(opts, :hpc_work_dir))
      |> put_if_present(:vault_dir, Keyword.get(opts, :vault_dir))
      |> put_if_present(:native_ssh, Keyword.get(opts, :native_ssh))

    try do
      {:ok, apply(hpc_module, :bootstrap, [bootstrap_opts])}
    rescue
      e ->
        {:error, {:hpc_bootstrap_failed, Exception.message(e)}}
    end
  end

  defp fetch_session(%{session: nil}) do
    {:error, :hpc_bootstrap_returned_no_session}
  end

  defp fetch_session(%{session: session}) do
    {:ok, session}
  end

  defp fetch_session(other) do
    {:error, {:unexpected_hpc_bootstrap_result, other}}
  end

  defp read_required_file(path) do
    case File.read(path) do
      {:ok, text} ->
        {:ok, text}

      {:error, reason} ->
        {:error, {:missing_generated_isabelle_file, path, reason}}
    end
  end

  defp ensure_remote_dir(hpc_module, session, remote_dir, opts) do
    command = """
    mkdir -p #{sh(remote_dir)}
    """

    remote_ok(hpc_module, session, command, opts)
  end

  defp upload_text(hpc_module, session, remote_dir, filename, text, opts) do
    remote_path = posix_join(remote_dir, filename)
    delimiter = heredoc_delimiter(text)

    command = """
    mkdir -p #{sh(remote_dir)}
    cat > #{sh(remote_path)} <<'#{delimiter}'
    #{text}
    #{delimiter}
    """

    remote_ok(hpc_module, session, command, opts)
  end

  defp run_remote_isabelle(hpc_module, session, remote_dir, spec, opts) do
    isabelle = Keyword.get(opts, :isabelle_bin, "isabelle")
    threads = Keyword.get(opts, :threads, 8)
    session_name = Keyword.get(opts, :session_name, spec.theory_name)
    remote_preamble = Keyword.get(opts, :remote_preamble, "")

    command = """
    set -e
    cd #{sh(remote_dir)}
    #{remote_preamble}
    #{sh(isabelle)} build -D . -o #{sh("threads=#{threads}")} #{sh(session_name)} 2>&1
    """

    remote(hpc_module, session, command, opts)
  end

  defp remote_ok(hpc_module, session, command, opts) do
    case remote(hpc_module, session, command, opts) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp remote(hpc_module, session, command, opts) do
    connect_opts = Keyword.get(opts, :connect_opts, [])

    try do
      output = apply(hpc_module, :connect!, [session, command, connect_opts])
      {:ok, output}
    rescue
      e ->
        {:error,
         {:hpc_remote_command_failed,
          %{
            message: Exception.message(e),
            command: command
          }}}
    end
  end

  defp remote_dir(spec, opts) do
    Keyword.get_lazy(opts, :remote_dir, fn ->
      run_id =
        "#{spec.theory_name}_#{System.system_time(:second)}"
        |> sanitize_path_component()

      "axiom_refiner_runs/#{run_id}"
    end)
  end

  defp put_if_present(opts, _key, nil), do: opts
  defp put_if_present(opts, _key, ""), do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp expand_path(nil), do: nil
  defp expand_path(path) when is_binary(path), do: Path.expand(path)
  defp expand_path(path), do: path

  defp posix_join(left, right) do
    left = String.trim_trailing(left, "/")
    right = String.trim_leading(right, "/")
    left <> "/" <> right
  end

  defp heredoc_delimiter(text) do
    base = "__AXIOM_REFINER_HEREDOC__"

    if String.contains?(text, base) do
      "__AXIOM_REFINER_HEREDOC_#{System.unique_integer([:positive])}__"
    else
      base
    end
  end

  defp sanitize_path_component(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_.-]/, "_")
  end

  defp sh(value) do
    value
    |> to_string()
    |> String.replace("'", "'\"'\"'")
    |> then(&"'#{&1}'")
  end
end
