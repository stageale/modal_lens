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
    #TODO
  end

  # später:
  # Sledgehammer, QuickCheck, Prove


  def reason(other, _spec, _opts) do
    # TODO
  end

  defp default_workdir do
    # TODO
  end

  defp timestamp do
    # TODO
  end
end
