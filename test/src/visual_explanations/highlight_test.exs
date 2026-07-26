defmodule Src.VisualExplanations.HighlightTest do
  use ExUnit.Case, async: true

  alias Src.VisualExplanations.Highlight

  test "builds a highlight from keyword attributes" do
    highlight =
      Highlight.new(
        basis: :semantic,
        world_scores: %{0 => 1.0, 2 => 0.8},
        edge_scores: %{{0, 2} => 1.0},
        tags: [:countermodel],
        metadata: %{reason: :query_failure}
      )

    assert highlight.basis == :semantic
    assert highlight.world_scores == %{0 => 1.0, 2 => 0.8}
    assert highlight.edge_scores == %{{0, 2} => 1.0}
    assert highlight.tags == [:countermodel]
  end

  test "produces an empty highlight" do
    assert Highlight.empty() == %Highlight{}
  end

  test "creates a highlight from a generic attribution map" do
    source = %{
      basis: :semantic,
      scope: :model,
      world_scores: %{1 => 1.0},
      edge_scores: %{},
      tags: [:ddl_witness],
      metadata: %{query: "Q"}
    }

    highlight =
      Highlight.from_map(source,
        source: :ddl_query_witness,
        metadata: %{iteration: 2}
      )

    assert highlight.world_scores == %{1 => 1.0}
    assert highlight.tags == [:ddl_witness]

    assert highlight.metadata == %{
             source: :ddl_query_witness,
             query: "Q",
             iteration: 2
           }
  end

  test "stores numerical attribution scores" do
    highlight =
      Highlight.new(
        basis: :pattern,
        scope: :cluster,
        world_scores: %{
          0 => 0.2,
          1 => 0.9
        },
        edge_scores: %{
          {0, 1} => 0.75
        }
      )

    assert highlight.basis == :pattern
    assert highlight.scope == :cluster
    assert highlight.world_scores == %{0 => 0.2, 1 => 0.9}
    assert highlight.edge_scores == %{{0, 1} => 0.75}
  end
end
