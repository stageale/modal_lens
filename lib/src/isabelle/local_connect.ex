defmodule Src.Isabelle.LocalConnect do

  def version(opts \\ []) do
    run(["version"], opts)
  end

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
        {:error, %{
          status: status,
          output: output,
          command: [isabelle | args]
        }}

      {:failed_to_start, exception} ->
        {:error, %{
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
      System.get_env("AXIOM_REFINER_ISABELLE_BIN") ||
      "isabelle"
  end

  @spec process_theory(
          binary()
          | maybe_improper_list(
              binary() | maybe_improper_list(any(), binary() | []) | char(),
              binary() | []
            )
        ) ::
          {:error,
           %{
             :output => any(),
             :status => :failed_to_start | pos_integer(),
             optional(:command) => [...]
           }}
          | {:ok, any()}
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

    args = [
      "process_theories",
      "-O",
      "-U",
      "-l",
      logic,
      "-o",
      "system_heaps=false",
      "-o",
      "threads=#{threads}",
    ] ++ file_args

    run(args, opts)
  end

  def process_theory(theory_path, opts \\ []) do
    process_theories([theory_path], opts)
  end
end
