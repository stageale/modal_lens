defmodule Src.Isabelle.LocalConnect do
  @moduledoc """
  Executes Isabelle commands on the local machine.

  The executable can be supplied through `:isabelle_bin`, configured through
  the environment, or resolved as `isabelle` from the system path.
  """

  @type command_error :: %{
          required(:status) => non_neg_integer() | :failed_to_start,
          required(:output) => String.t(),
          optional(:command) => [String.t()]
        }

  @type result :: {:ok, String.t()} | {:error, command_error()}

  @doc "Returns the installed Isabelle version."
  @spec version() :: result()
  @spec version(keyword()) :: result()
  def version(opts \\ []) do
    run(["version"], opts)
  end

  @doc "Builds the generated Isabelle session in `workdir`."
  @spec build(Path.t(), %{required(:theory_name) => String.t()}) :: result()
  @spec build(Path.t(), %{required(:theory_name) => String.t()}, keyword()) :: result()
  def build(workdir, spec, opts \\ []) do
    threads =
      Keyword.get(
        opts,
        :threads,
        min(System.schedulers_online(), 2)
      )

    session_name = Map.fetch!(spec, :theory_name)

    args = [
      "build",
      "-j",
      "1",
      "-d",
      workdir,
      "-o",
      "system_heaps=false",
      "-o",
      "threads=#{threads}",
      session_name
    ]

    run(args, opts)
  end

  @doc "Reads the verbose build log for an Isabelle session."
  @spec build_log(String.t()) :: result()
  @spec build_log(String.t(), keyword()) :: result()
  def build_log(session_name, opts \\ []) do
    run(
      [
        "build_log",
        "-v",
        "-U",
        "-o",
        "system_heaps=false",
        session_name
      ],
      opts
    )
  end

  @doc "Returns the configured Isabelle executable."
  @spec configured_isabelle_bin() :: String.t()
  @spec configured_isabelle_bin(keyword()) :: String.t()
  def configured_isabelle_bin(opts \\ []) do
    isabelle_bin(opts)
  end

  defp run(args, opts) do
    isabelle = isabelle_bin(opts)

    result =
      try do
        System.cmd(
          isabelle,
          args,
          stderr_to_stdout: true
        )
      rescue
        exception in ErlangError ->
          {:failed_to_start, exception}
      end

    case result do
      {output, 0} ->
        {:ok, output}

      {output, status} when is_integer(status) ->
        {:error,
         %{
           status: status,
           output: output,
           command: [isabelle | args]
         }}

      {:failed_to_start, exception} ->
        {:error,
         %{
           status: :failed_to_start,
           output:
             "Could not start Isabelle executable. " <>
               "Tried: #{inspect(isabelle)}. " <>
               "Error: #{Exception.message(exception)}"
         }}
    end
  end

  defp isabelle_bin(opts) do
    Keyword.get(opts, :isabelle_bin) ||
      System.get_env("MODAL_LENS_ISABELLE_BIN") ||
      "isabelle"
  end

  @doc "Processes multiple Isabelle theory files in one invocation."
  @spec process_theories([Path.t()]) :: result()
  @spec process_theories([Path.t()], keyword()) :: result()
  def process_theories(theory_paths, opts \\ []) when is_list(theory_paths) do
    logic = Keyword.get(opts, :logic, "HOL")

    threads =
      Keyword.get(
        opts,
        :threads,
        min(System.schedulers_online(), 2)
      )

    file_args =
      theory_paths
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Path.expand/1)
      |> Enum.uniq()
      |> Enum.flat_map(fn path -> ["-f", path] end)

    args =
      [
        "process_theories",
        "-O",
        "-U",
        "-l",
        logic,
        "-o",
        "system_heaps=false",
        "-o",
        "threads=#{threads}"
      ] ++ file_args

    run(args, opts)
  end

  def process_theory(theory_path, opts \\ []) do
    process_theories([theory_path], opts)
  end
end
