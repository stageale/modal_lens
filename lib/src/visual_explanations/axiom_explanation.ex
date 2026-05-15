defmodule Src.VisualExplanations.AxiomExplanation do
  @moduledoc """
  Visual explanation layer for axiomsugg suggestions.

  This module should identify which worlds and edges are respnsible
  for violations of frame conditions.
  """

  alias Src.HardcodedRefinement.FrameAnalysis

  defstruct [
    :axiom,
    :title,
    :satisfied?,
    violations: [],
    responsible_edges: MapSet.new(),
    missing_edges: MapSet.new(),
    responsible_worlds: MapSet.new()
  ]

  @supported_axioms [
    :serial,
    :reflexive,
    :symmetric,
    :transitive,
    :euclidean,
    :functional
  ]



  def supported_axioms do
    # TODO: return all supported frame axioms
    @supported_axioms
  end

  def explain(%FrameAnalysis{} = analysis, axiom) do
    # TODO: dispatch to the corresponding axiom explanation function
    case axiom do
      :serial ->
        serial_explanation(analysis)
      :reflexive ->
        reflexive_explanation(analysis)
      :symmetry ->
        symmetric_explanation(analysis)
      :transitive ->
        transitive_explanation(analysis)
      :euclidean ->
        euclidean_explanation(analysis)
      :functional ->
        functional_explanation(analysis)
    end
  end

  def explain_all(%FrameAnalysis{} = analysis) do
    @supported_axioms
    |> Enum.all?(&(&explain/2))
    #* or
    #* @supported_axioms
    #* |> Enum.all?(fn ax -> explain(analysis, axiom) end)
  end

  defp serial_explanation(%FrameAnalysis{} = analysis) do
    # TODO: explain seriality violations using dead-end worlds
    #* analysis.dead_ends
  end

  defp reflexive_explanation(%FrameAnalysis{} = analysis) do
    # TODO: explain reflexivity violations using asymmetric edges

  end

  defp transitive_explanation(%FrameAnalysis{} = analysis) do
    # TODO: explain transitivity violations using missing hulls
  end

  defp euclidean_explanation(%FrameAnalysis{} = analysis) do
    # TODO: explain euclidean violations using missing spans
  end

  defp functional_explanation(%FrameAnalysis{} = analysis) do
    # TODO: explain functionality violations using conflicting outgoing edges
  end

  defp build(axiom, attrs) do
    # TODO: construct the final AxiomExplanation struct/map
  end

  defp responsible_edges(axiom, violations) do
    # TODO: compute existing edges responsible for the given violations
  end

  defp missing_edges(axiom, violations) do
    # TODO: compute missing edges that could repair the given violations
  end

  defp responsible_worlds(axiom, violations) do
    # TODO: compute worlds involved in the given violations
  end

  defp worlds_from_edges(edges) do
    # TODO: collect all worlds occuring in a set/list of edges
  end

  defp normalise_pair(violation) do
    # TODO: normalise a two-world violation into {w, v}
  end

  defp normalise_triple(violation) do
    # TODO: normalise a three-world violation into {w, v, u}
  end
end
