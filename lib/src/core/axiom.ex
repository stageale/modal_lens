defmodule Src.Core.Axiom do
  @moduledoc """
  Deprecated! Compatibility wrapper for blocking axiom generation.

  Prefer 'Src.Core.BlockingAxiom' in new code.
  """

  alias Src.Core.BlockingAxiom
  alias Src.Core.Model

  defdelegate sanitize_name(name), to: BlockingAxiom
  defdelegate source_stem(model), to: BlockingAxiom
  defdelegate exact_structure_formula(model, opts \\ []), to: BlockingAxiom

  def blocking_axiom(%Model{} = model, opts \\ []) do
    BlockingAxiom.blocking_axiom(model, opts)
  end
end
