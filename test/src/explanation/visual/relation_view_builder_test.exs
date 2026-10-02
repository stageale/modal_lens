defmodule Src.Explanation.Visual.RelationViewBuilderTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.Modality
  alias Src.Explanation.Visual.GraphView.ViewEdge
  alias Src.Explanation.Visual.RelationViewBuilder

  describe "build/3" do
    test "preserves the original relation independently of the view edges" do
      modality =
        belief_modality(
          "RBel",
          [
            {0, 0},
            {0, 1},
            {1, 1}
          ]
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1]
        )

      assert view.original_edges ==
               MapSet.new([
                 {0, 0},
                 {0, 1},
                 {1, 1}
               ])

      assert view.modality_id ==
               Modality.id(modality)

      assert view.filter_key == "belief"
      assert view.kind == :belief
      assert view.agent == "provider"
    end

    test "supports an explicit visualization filter key" do
      modality =
        belief_modality(
          "RBel",
          [{0, 1}]
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1],
          filter_key: :epistemic
        )

      assert view.filter_key == "epistemic"
    end
  end

  describe "relation properties" do
    test "recognizes a reflexive transitive but non-symmetric relation" do
      modality =
        belief_modality(
          "R",
          [
            {0, 0},
            {1, 1},
            {2, 2},
            {0, 1},
            {1, 2},
            {0, 2}
          ]
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1, 2]
        )

      assert view.properties == %{
               reflexive: true,
               symmetric: false,
               transitive: true
             }
    end

    test "recognizes an equivalence relation" do
      modality =
        belief_modality(
          "R",
          complete_relation([0, 1, 2])
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1, 2]
        )

      assert view.properties == %{
               reflexive: true,
               symmetric: true,
               transitive: true
             }
    end
  end

  describe "reflexive loop reduction" do
    test "removes loops when the relation is globally reflexive" do
      modality =
        belief_modality(
          "R",
          [
            {0, 0},
            {1, 1},
            {0, 1}
          ]
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1]
        )

      assert view.properties.reflexive

      refute Enum.any?(
               view.edges,
               fn %ViewEdge{
                    source: source,
                    target: target
                  } ->
                 source == target
               end
             )

      assert edge_tuples(view) == [
               {0, 1, :forward}
             ]
    end

    test "keeps a loop when the relation is not globally reflexive" do
      modality =
        belief_modality(
          "R",
          [
            {0, 0},
            {0, 1}
          ]
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1]
        )

      refute view.properties.reflexive

      assert {0, 0, :forward} in edge_tuples(view)
      assert {0, 1, :forward} in edge_tuples(view)
    end
  end

  describe "reciprocal edge reduction" do
    test "collapses a local reciprocal pair to an undirected view edge" do
      modality =
        belief_modality(
          "R",
          [
            {0, 1},
            {1, 0},
            {1, 2}
          ]
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1, 2]
        )

      refute view.properties.symmetric

      assert edge_tuples(view) == [
               {0, 1, :undirected},
               {1, 2, :forward}
             ]
    end

    test "uses undirected edges when the whole relation is symmetric" do
      modality =
        belief_modality(
          "R",
          [
            {0, 1},
            {1, 0},
            {1, 2},
            {2, 1}
          ]
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1, 2]
        )

      assert view.properties.symmetric

      assert edge_tuples(view) == [
               {0, 1, :undirected},
               {1, 2, :undirected}
             ]
    end
  end

  describe "transitive reduction" do
    test "removes reflexive loops and transitively implied edges from a partial order" do
      modality =
        belief_modality(
          "R",
          [
            {0, 0},
            {1, 1},
            {2, 2},
            {0, 1},
            {1, 2},
            {0, 2}
          ]
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1, 2]
        )

      assert view.properties == %{
               reflexive: true,
               symmetric: false,
               transitive: true
             }

      assert edge_tuples(view) == [
               {0, 1, :forward},
               {1, 2, :forward}
             ]
    end

    test "reduces an equivalence relation to an undirected generator" do
      modality =
        belief_modality(
          "R",
          complete_relation([0, 1, 2])
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1, 2]
        )

      assert view.properties == %{
               reflexive: true,
               symmetric: true,
               transitive: true
             }

      assert edge_tuples(view) == [
               {0, 1, :undirected},
               {1, 2, :undirected}
             ]
    end

    test "reduces a strongly connected component without claiming global symmetry" do
      modality =
        belief_modality(
          "R",
          [
            # SCC {0, 1}
            {0, 0},
            {1, 1},
            {0, 1},
            {1, 0},

            # Singleton SCCs
            {2, 2},
            {3, 3},

            # Transitive relation between SCCs
            {0, 2},
            {1, 2},
            {0, 3},
            {1, 3},
            {2, 3}
          ]
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1, 2, 3]
        )

      assert view.properties == %{
               reflexive: true,
               symmetric: false,
               transitive: true
             }

      assert edge_tuples(view) == [
               {0, 1, :undirected},
               {0, 2, :forward},
               {2, 3, :forward}
             ]
    end

    test "does not transitively reduce a non-transitive relation" do
      modality =
        belief_modality(
          "R",
          [
            {0, 1},
            {1, 2}
          ]
        )

      view =
        RelationViewBuilder.build(
          modality,
          [0, 1, 2]
        )

      refute view.properties.transitive

      assert edge_tuples(view) == [
               {0, 1, :forward},
               {1, 2, :forward}
             ]
    end
  end

  describe "validation" do
    test "rejects relation edges referring to worlds outside the model" do
      modality =
        belief_modality(
          "R",
          [
            {0, 1},
            {1, 2}
          ]
        )

      assert_raise ArgumentError,
                   ~r/outside the model world set/,
                   fn ->
                     RelationViewBuilder.build(
                       modality,
                       [0, 1]
                     )
                   end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp belief_modality(symbol, edges, opts \\ []) do
    Modality.new!(
      symbol,
      :belief,
      edges,
      Keyword.put_new(
        opts,
        :agent,
        "provider"
      )
    )
  end

  defp edge_tuples(view) do
    Enum.map(
      view.edges,
      fn %ViewEdge{
           source: source,
           target: target,
           direction: direction
         } ->
        {source, target, direction}
      end
    )
  end

  defp complete_relation(worlds) do
    for source <- worlds,
        target <- worlds do
      {source, target}
    end
  end
end
