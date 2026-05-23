defmodule Src.Interface.Isabelle.HOLEmbedding do
  @moduledoc """
  Generates Isabelle/HOL theory files used as input for Isabelle/Nitpick

  This module is intentionally an interface module:
  it translates our internal/refinement-side ideas into Isabelle/HOL syntax.
  """

  defstruct [
    theory_name: "Axiom_Refiner_Run",
    imports: ["Main"],
    type_name: "i",
    relation_name: "r",
    atoms: [],
    axioms: [],
    goal: "False",
    nitpick_options: ["user_axioms"]
  ]

  def new(opts \\ []) do
    #TODO
  end

  def render_theory(%__MODULE__{} = spec) do
    #TODO
    """
    theory #{spec.theory_name}
      ...
    """
  end

  def write_theory!(%__MODULE__{} = spec, dir) do
    #TODO
  end

  def write_root!(%__MODULE__{} = spec, dir) do
    #TODO
  end

  defp render_base_signature(spec) do
    #TODO
  end

  defp render_atoms(spec) do
    #TODO
  end

  defp render_axioms(spec) do
    #TODO
  end

  defp render_frame_axiom_definitions(spec) do
    #TODO
  end

  def frame_axiom(r \\ "r", kind)

  #TODO Pattern Matching
end
