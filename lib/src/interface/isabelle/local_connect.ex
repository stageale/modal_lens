defmodule Src.Interface.Isabelle.LocalConnect do
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

  def process_theory(theory_path, opts \\ []) do
    theory_path = Path.expand(theory_path)
    logic = Keyword.get(opts, :logic, "HOL")

    threads =
      Keyword.get(
        opts,
        :threads,
        min(System.schedulers_online(), 2)
      )

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
      "-f",
      theory_path
    ]

    run(args, opts)
  end
end
