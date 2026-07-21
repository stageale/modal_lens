defmodule Src.VisualExplanations.HighlightTest do
  use ExUnit.Case, async: true

  alias Src.VisualExplanations.Highlight

  test "builds and normalizes a highlight from keyword attributes" do
    highlight =
      Highlight.new(
        responsible_worlds: [0, 2],
        responsible_edges: [{0, 2}],
        missing_edges: [{2, 1}],
        tags: [:countermodel],
        metadata: %{reason: :query_failure}
      )

    assert highlight.responsible_worlds == MapSet.new([0, 2])
    assert highlight.responsible_edges == MapSet.new([{0, 2}])
    assert highlight.missing_edges == MapSet.new([{2, 1}])
    assert highlight.tags == [:countermodel]
    assert highlight.metadata.reason == :query_failure
  end

  test "produces an empty highlight" do
    assert Highlight.empty() == %Highlight{}
  end

  test "creates a highlight from a generic explanation map" do
    explanation = %{
      responsible_worlds: MapSet.new([1]),
      responsible_edges: [{1, 2}],
      missing_edges: [],
      tags: [:ddl_witness],
      metadata: %{query: "Q"}
    }

    highlight =
      Highlight.from_map(explanation,
        source: :ddl_query_witness,
        metadata: %{iteration: 2}
      )

    assert highlight.responsible_worlds == MapSet.new([1])
    assert highlight.responsible_edges == MapSet.new([{1, 2}])
    assert highlight.tags == [:ddl_witness]

    assert highlight.metadata == %{
             query: "Q",
             iteration: 2,
             source: :ddl_query_witness
           }
  end

  test "adapts legacy explanation maps without a struct dependency" do
    explanation = %{
      axiom: :serial,
      status: :violated,
      responsible_worlds: [0],
      responsible_edges: [],
      missing_edges: [],
      tags: [:legacy]
    }

    highlight = Highlight.from_explanation(explanation)

    assert highlight.responsible_worlds == MapSet.new([0])
    assert highlight.metadata.source == :axiom_explanation
    assert highlight.metadata.axiom == :serial
    assert highlight.metadata.status == :violated
  end
end
