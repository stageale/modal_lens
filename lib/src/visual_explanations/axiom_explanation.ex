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
    :euclidean
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

      :symmetric ->
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
      keywords: ["seriality", "dead-end", "no outgoing edges"]
    )
  end

  defp reflexive_explanation(%FrameAnalysis{} = analysis) do
    build(:reflexive,
      title: "Reflexivity",
      formula: "∀u. R u u",
      violations: analysis.missing_loops,
      summary: "Reflexivity is violated by loops",
      tags: [:frame_condition, :modal_axiom, :reflexive],
      keywords: ["reflexivity", "missing loops"]
    )
  end

  defp symmetric_explanation(%FrameAnalysis{} = analysis) do
    build(:symmetric,
      title: "Symmetry",
      formula: "∀u v. (R u v → R v u)",
      violations: analysis.antisymmetries,
      summary: "Symmetry is violated by worlds without self-loops",
      tags: [:frame_condition, :modal_axiom, :symmetric],
      keywords: ["symmetry", "missing loops"]
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
    build(:euclidean,
      title: "Euclideanness",
      formula: "∀u v w.((R u v ∧ R u w) → R v w)",
      violations: analysis.missing_spans,
      summary: "Euclidity is violated by two edges without spanning edge",
      tags: [:frame_condition, :modal_axiom, :euclidean],
      keywords: ["euclidean", "missing span"]
    )
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
        Enum.map(violations, fn {u, v} -> {v, u} end)

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
        Enum.map(violations, fn u -> {u, u} end)

      :symmetric ->
        violations

      :transitive ->
        Enum.map(violations, fn {u, _, w} -> {u, w} end)

      :euclidean ->
        Enum.map(violations, fn {_, v, w} -> {v, w} end)
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
end
