defmodule Src.Interface.Isabelle.LocalConnect do
  def version(opts \\ []) do
    run(["version"], opts)
  end

  def build(workdir, spec, opts \\ []) do
    threads = Keyword.get(opts, :threads, System.schedulers_online())

    args = [
      "build",
      "-D",
      workdir,
      "-o",
      "threads=#{threads}",
      spec.theory_name
    ]

    run(args, opts)
  end

  def configured_isabelle_bin(opts \\ []) do
    isabelle_bin(opts)
  end

  defp run(args, opts) do
    isabelle = isabelle_bin(opts)

    result =
      try do
        System.cmd(isabelle, args, stderr_to_stdout: true)
      rescue
        e in ErlangError ->
          {:failed_to_start, e}
      end

    case result do
      {output, 0} ->
        {:ok, output}

      {output, status} when is_integer(status) ->
        {:error, %{status: status, output: output}}

      {:failed_to_start, e} ->
        {:error,
         %{
           status: :failed_to_start,
           output:
             "Could not start Isabelle executable. Tried: #{inspect(isabelle)}. Error: #{Exception.message(e)}"
         }}
    end
  end

  defp isabelle_bin(opts) do
    Keyword.get(opts, :isabelle_bin) ||
      System.get_env("AXIOM_REFINER_ISABELLE_BIN") ||
      "isabelle"
  end
end
