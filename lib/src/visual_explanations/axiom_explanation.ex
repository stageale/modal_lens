defmodule Src.VisualExplanations.AxiomExplanation do
  @moduledoc """
  Visual explanation layer for axiomsugg suggestions.

  This module should identify which worlds and edges are respnsible
  for violations of frame conditions.

  The corresponding struct is the central exchange format between:
    - FrameAnalysis
    - scoring / ranking
    - viusual highlights
    - textual explanations
    - later LLM explanation generation
  """

  alias Src.HardcodedRefinement.FrameAnalysis

  defstruct [
    :axiom,
    :title,
    :formula,
    :status,
    :summary,

    violations: [],
    responsible_edges: MapSet.new(),
    missing_edges: MapSet.new(),
    responsible_worlds: MapSet.new(),

    tags: [],
    keywords: [],
    text_variants: %{},
    metadata: %{}
  ]

  @supported_axioms [
    :serial,
    :reflexive,
    :symmetric,
    :transitive,
    :euclidean,
    #!:functional
  ]



  def supported_axioms do
    # TODO: return all supported frame axioms
    @supported_axioms
  end

  def explain(%FrameAnalysis{} = analysis, axiom) do
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
      #!:functional ->
        #!functional_explanation(analysis)
    end
  end

  def explain_all(%FrameAnalysis{} = analysis) do
    @supported_axioms
    |> Enum.map(fn ax -> explain(analysis, ax) end)
  end

  defp serial_explanation(%FrameAnalysis{} = analysis) do
    build(:serial,
      title: "Seriality",
      formula: "∀u. ∃v. R u v",
      violations: analysis.dead_ends,
      summary: "Seriality is violated by dead-end worlds that have no outgoing edges",
      tags: [:frame_condition, :modal_axiom, :serial],
      keywords: ["seriality", "dead-end", "no outgoing edges"],
      responsible_edges: responsible_edges(:serial, analysis.dead_ends),
      missing_edges: missing_edges(:serial, analysis.dead_ends),
      responsible_worlds: responsible_worlds(:serial, analysis.dead_ends)
    )
  end

  defp reflexive_explanation(%FrameAnalysis{} = analysis) do
    build(:reflexive,
      title: "Reflexivity",
      formula: "∀u. R u u",
      violations: analysis.missing_loops,
      summary: "Reflexivity is violated by loops",
      tags: [:frame_condition, :modal_axiom, :reflexive],
      keywords: ["reflexivity", "missing loops"],
      responsible_edges: responsible_edges(:reflexive, analysis.missing_loops),
      missing_edges: missing_edges(:reflexive, analysis.missing_loops),
      responsible_worlds: responsible_worlds(:reflexive, analysis.missing_loops)
    )
  end

  defp symmetric_explanation(%FrameAnalysis{} = analysis) do
    build(:reflexive,
      title: "Reflexivity",
      formula: "∀u v. (R u v → R v u)",
      violations: analysis.antisymmetries,
      summary: "Reflexivity is violated by loops",
      tags: [:frame_condition, :modal_axiom, :reflexive],
      keywords: ["reflexivity", "missing loops"],
      responsible_edges: responsible_edges(:reflexive, analysis.missing_loops),
      missing_edges: missing_edges(:reflexive, analysis.missing_loops),
      responsible_worlds: responsible_worlds(:reflexive, analysis.missing_loops)
    )
  end

  defp transitive_explanation(%FrameAnalysis{} = analysis) do
    build(:transitive,
      title: "Transitivity",
      formula: "∀u v w.((R u v ∧ R v w) → R u w)",
      violations: analysis.missing_hulls,
      summary: "Transitivity is violated by paths of length two without shortcut edge",
      tags: [:frame_condition, :modal_axiom, :transitivity],
      keywords: ["transitivity", "path", "missing shortcut"]
    )
  end

  defp euclidean_explanation(%FrameAnalysis{} = analysis) do
    # TODO: explain euclidean violations using missing spans
  end

  #!defp functional_explanation(%FrameAnalysis{} = analysis) do
    #! TODO: explain functionality violations using conflicting outgoing edges
  #!end

  defp build(axiom, attrs) do
    # TODO: construct the final AxiomExplanation struct/map
    violations = Keyword.get(attrs, :violations, [])

    %__MODULE__{
      axiom: axiom,
      title: Keyword.get(attrs, :title, Atom.to_string(axiom)),
      formula: Keyword.get(attrs, :formula),
      status: if(Enum.empty?(violations), do: :satisfied, else: :violated),
      summary: Keyword.get(attrs, :summary),

      violations: violations,
      responsible_edges:
        attrs
        |> Keyword.get(:responsible_edges, responsible_edges(axiom, violations))
        |> MapSet.new(),
      missing_edges:
        attrs
        |> Keyword.get(:missing_edges, missing_edges(axiom, violations))
        |> MapSet.new(),
      responsible_worlds:
        attrs
        |> Keyword.get(:responsible_worlds, responsible_worlds(axiom, violations))
        |> MapSet.new(),

      tags: Keyword.get(attrs, :tags, [axiom]),
      keywords: Keyword.get(attrs, :keywords, []),
      text_variants: Keyword.get(attrs, :text_variants, %{}),
      metadata: Keyword.get(attrs, :metadata, %{})
    }
  end

  defp responsible_edges(axiom, violations) do
    case axiom do
      :serial ->
        []
      :reflexive ->
        []
      :symmetric ->
        Enum.flat_map(violations, fn {u, v} -> {v, u} end)
      :transitive ->
        Enum.flat_map(violations, fn {u, v, w} -> [{u, v}, {v, w}] end)
      :euclidean ->
        Enum.flat_map(violations, fn {u, v, w} -> [{u, v}, {u, w}] end)
      #!:functional ->
    end
  end

  defp missing_edges(axiom, violations) do
    case axiom do
      :serial ->
        []
      :reflexive ->
        Enum.flat_map(violations, fn u -> {u, u} end)
      :symmetric ->
        violations
      :transitive ->
        Enum.flat_map(violations, fn {u, v, w} -> {u, w} end)
      :euclidean ->
        Enum.flat_map(violations, fn {u, v, w} -> {v, w} end)
      #!:functional ->
    end
  end

  defp responsible_worlds(axiom, violations) do
    case axiom do
      :serial ->
        violations
      :reflexive ->
        violations
      :symmetric ->
        Enum.flat_map(violations, fn {u, v} -> [u, v] end)
      :transitive ->
        Enum.flat_map(violations, fn {u, v, w} -> [u, v, w] end)
      :euclidean ->
        Enum.flat_map(violations, fn {u, v, w} -> [u, v, w] end)
      #!:functional ->
    end
  end

  defp worlds_from_edges(edges), do: Enum.flat_map(edges, fn {u, v} -> [u, v] end)

#  defp normalise_pair(violation) do
#    # TODO: normalise a two-world violation into {w, v}
#  end

#  defp normalise_triple(violation) do
#    # TODO: normalise a three-world violation into {w, v, u}
#  end
end
