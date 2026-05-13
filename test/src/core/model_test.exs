defmodule Src.Core.ModelTest do
  use ExUnit.Case

  alias Src.Core.Model

  test "computes world names" do
    model = %Model{cardinality: 3, relation_name: "R"}

    assert Model.world_name(model, 0) == "i1"
    assert Model.world_name(model, 2) == "i3"
  end

  test "splits self loops and proper edges" do
    model = %Model{
      cardinality: 3,
      relation_name: "R",
      edges: MapSet.new([{0, 0}, {0, 1}, {2, 2}])
    }

    assert Model.self_loops(model) == MapSet.new([{0, 0}, {2, 2}])
    assert Model.proper_edges(model) == MapSet.new([{0, 1}])
  end

  test "builds labels from valuations" do
    model = %Model{
      cardinality: 2,
      relation_name: "R",
      valuations: %{
        "go" => [true, false],
        "tell" => [false, true]
      }
    }

    assert Model.label_for_world(model, 0) == "i1: go, ¬tell"
    assert Model.label_for_world(model, 1) == "i2: ¬go, tell"
  end

  test "builds relation matrix" do
    model = %Model{
      cardinality: 3,
      relation_name: "R",
      edges: MapSet.new([{0, 1}, {2, 2}])
    }

    assert Model.relation_matrix(model) == [
             [false, true, false],
             [false, false, false],
             [false, false, true]
           ]
  end

  test "builds summary" do
    model = %Model{
      source: "example.txt",
      kind: :countermodel,
      cardinality: 2,
      relation_name: "R",
      initial_world: 1,
      edges: MapSet.new([{0, 1}, {1, 1}]),
      valuations: %{"go" => [true, false]},
      warnings: [%{message: "example warning"}]
    }

    assert Model.as_summary(model) == %{
             source: "example.txt",
             kind: :countermodel,
             cardinality: 2,
             relation: "R",
             initial_world: "i2",
             edge_count: 2,
             atoms: ["go"],
             warnings: ["example warning"]
           }
  end
end
