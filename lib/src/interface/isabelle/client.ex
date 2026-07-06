defmodule Src.Interface.Isabelle.Client do
  @moduledoc """
  High-level entry point for Isabelle-based reasoning.

  The important contract:
  reason(:nitpick, ...) writes a Nitpick log to a .txt file
  that the existing project pipeline can already consume.
  """

  alias Src.Interface.Isabelle.HOLEmbedding
  alias Src.Interface.Isabelle.LocalConnect
  alias Src.Interface.Isabelle.HPCConnect

  def reason(:nitpick, %HOLEmbedding{} = spec, opts \\ []) do
    backend = Keyword.get(opts, :backend, :local)
    workdir = Keyword.get(opts, :workdir, default_workdir())
    output_file = Keyword.get(opts, :output_file, Path.join(workdir, "nitpick-output.txt"))

    HOLEmbedding.write_root!(spec, workdir)
    HOLEmbedding.write_theory!(spec, workdir)

    result =
      case backend do
        :local ->
          LocalConnect.run(workdir, spec, opts)

        :hpc_connect ->
          HPCConnect.run(workdir, spec, opts)

        other ->
          {:error, {:unknown_backend, other}}
      end

    case result do
      {:ok, log} ->
        File.write!(output_file, log)
        {:ok, %{output_file: output_file, log: log, backend: backend}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # später:
  # Sledgehammer, QuickCheck, Prove


  def reason(other, _spec, _opts) do
    {:error, {:unsupported_reasoning_mode, other}}
  end

  defp default_workdir do
    Path.join(["tmp", "isabelle", timestamp()])
  end

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.to_iso8601(:basic)
    |> String.replace(~r/[^0-9A-Za-z]/, "_")
  end
end
