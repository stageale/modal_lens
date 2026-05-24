defmodule Src.Interface.Isabelle.LocalConnect do
  @moduledoc """
  Local Isabelle execution backend
  """

  def run(workdir, spec, opts \\ []) do
    isabelle = Keyword.get(opts, :isabelle_bin, "isabelle")
    threads = Keyword.get(opts, :threads, System.schedulers_online())

    args = [
      "build",
      "-D", workdir,
      "-o", "threads=#{threads}",
      spec.theory_name
    ]

    case System.cmd(isabelle, args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {output, status} ->
        {:error, %{status: status, output: output}}
    end
  end
end
