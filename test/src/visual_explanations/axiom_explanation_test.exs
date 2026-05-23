defmodule Src.VisualExplanations.AxiomExplanationTest do
  use ExUnit.Case, async: true

  alias Src.VisualExplanations.AxiomExplanation
  alias Src.HardcodedRefinement.FrameAnalysis

  defp analysis(attrs \\ []) do
    struct(FrameAnalysis, attrs)
  end

  describe "supported_axioms/0" do
    test "returns all currently supported axioms" do
      assert AxiomExplanation.supported_axioms() == [
               :serial,
               :reflexive,
               :symmetric,
               :transitive,
               :euclidean
             ]
    end
  end

  describe "explain/2 for seriality" do
    test "marks dead-end worlds as responsible worlds" do
      explanation =
        analysis(dead_ends: [0, 2])
        |> AxiomExplanation.explain(:serial)

      assert explanation.axiom == :serial
      assert explanation.title == "Seriality"
      assert explanation.status == :violated
      assert explanation.violations == [0, 2]

      assert explanation.responsible_worlds == MapSet.new([0, 2])
      assert explanation.responsible_edges == MapSet.new()
      assert explanation.missing_edges == MapSet.new()

      assert :serial in explanation.tags
      assert "dead-end" in explanation.keywords
    end

    test "is satisfied when there are no dead ends" do
      explanation =
        analysis(dead_ends: [])
        |> AxiomExplanation.explain(:serial)

      assert explanation.status == :satisfied
      assert explanation.violations == []
      assert explanation.responsible_worlds == MapSet.new()
      assert explanation.responsible_edges == MapSet.new()
      assert explanation.missing_edges == MapSet.new()
    end
  end

  describe "explain/2 for reflexivity" do
    test "turns missing loop worlds into missing self-loop edges" do
      explanation =
        analysis(missing_loops: [0, 2])
        |> AxiomExplanation.explain(:reflexive)

      assert explanation.axiom == :reflexive
      assert explanation.status == :violated
      assert explanation.violations == [0, 2]

      assert explanation.responsible_worlds == MapSet.new([0, 2])
      assert explanation.responsible_edges == MapSet.new()
      assert explanation.missing_edges == MapSet.new([{0, 0}, {2, 2}])

      assert :reflexive in explanation.tags
      assert "reflexivity" in explanation.keywords
    end
  end

  describe "explain/2 for symmetry" do
    test "uses antisymmetries as missing edges and reversed edges as responsible edges" do
      explanation =
        analysis(antisymmetries: [{0, 1}, {2, 3}])
        |> AxiomExplanation.explain(:symmetric)

      assert explanation.axiom == :symmetric
      assert explanation.status == :violated
      assert explanation.violations == [{0, 1}, {2, 3}]

      # Important project convention:
      # antisymmetries stores the missing edge.
      #
      # Missing:
      #   0 -> 1
      #   2 -> 3
      #
      # Responsible existing reverse edges:
      #   1 -> 0
      #   3 -> 2
      assert explanation.missing_edges == MapSet.new([{0, 1}, {2, 3}])
      assert explanation.responsible_edges == MapSet.new([{1, 0}, {3, 2}])
      assert explanation.responsible_worlds == MapSet.new([0, 1, 2, 3])
    end
  end

  describe "explain/2 for transitivity" do
    test "explains missing hulls by path edges and missing shortcut edges" do
      explanation =
        analysis(missing_hulls: [{0, 1, 2}, {2, 3, 4}])
        |> AxiomExplanation.explain(:transitive)

      assert explanation.axiom == :transitive
      assert explanation.status == :violated
      assert explanation.violations == [{0, 1, 2}, {2, 3, 4}]

      assert explanation.responsible_edges ==
               MapSet.new([
                 {0, 1},
                 {1, 2},
                 {2, 3},
                 {3, 4}
               ])

      assert explanation.missing_edges ==
               MapSet.new([
                 {0, 2},
                 {2, 4}
               ])

      assert explanation.responsible_worlds == MapSet.new([0, 1, 2, 3, 4])

      assert :transitivity in explanation.tags
      assert "missing shortcut" in explanation.keywords
    end
  end

  describe "explain/2 for euclideanness" do
    test "explains missing spans by common-source edges and missing span edges" do
      explanation =
        analysis(missing_spans: [{0, 1, 2}, {3, 4, 5}])
        |> AxiomExplanation.explain(:euclidean)

      assert explanation.axiom == :euclidean
      assert explanation.status == :violated
      assert explanation.violations == [{0, 1, 2}, {3, 4, 5}]

      assert explanation.responsible_edges ==
               MapSet.new([
                 {0, 1},
                 {0, 2},
                 {3, 4},
                 {3, 5}
               ])

      assert explanation.missing_edges ==
               MapSet.new([
                 {1, 2},
                 {4, 5}
               ])

      assert explanation.responsible_worlds == MapSet.new([0, 1, 2, 3, 4, 5])

      assert :euclidean in explanation.tags
      assert "missing span" in explanation.keywords
    end
  end

  describe "explain_all/1" do
    test "returns one explanation for each supported axiom" do
      explanations =
        analysis(
          dead_ends: [0],
          missing_loops: [1],
          antisymmetries: [{2, 3}],
          missing_hulls: [{3, 4, 5}],
          missing_spans: [{6, 7, 8}]
        )
        |> AxiomExplanation.explain_all()

      assert Enum.map(explanations, & &1.axiom) == [
               :serial,
               :reflexive,
               :symmetric,
               :transitive,
               :euclidean
             ]

      assert Enum.all?(explanations, fn explanation ->
               explanation.status == :violated
             end)
    end

    test "returns satisfied explanations when there are no violations" do
      explanations =
        analysis(
          dead_ends: [],
          missing_loops: [],
          antisymmetries: [],
          missing_hulls: [],
          missing_spans: []
        )
        |> AxiomExplanation.explain_all()

      assert Enum.all?(explanations, fn explanation ->
               explanation.status == :satisfied
             end)

      assert Enum.all?(explanations, fn explanation ->
               explanation.responsible_edges == MapSet.new() and
                 explanation.missing_edges == MapSet.new() and
                 explanation.responsible_worlds == MapSet.new()
             end)
    end
  end
end
