defmodule Src.Core.ModelTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model
  alias Src.Core.Model.DDL
  alias Src.Core.Model.SDL
  alias Src.Core.ParseWarning

  defp sdl_model do
    %SDL{
      source: "example.txt",
      kind: :countermodel,
      cardinality: 3,
      relation_name: "R",
      initial_world: 1,
      edges: MapSet.new([{0, 0}, {0, 1}, {2, 2}]),
      valuations: %{
        "go" => [true, false, true],
        "tell" => [false, true, false]
      },
      warnings: [%ParseWarning{message: "example warning"}]
    }
  end

  defp ddl_model do
    %DDL{
      source: nil,
      kind: :model,
      cardinality: 2,
      relation_name: "R",
      actual_world: 0,
      edges: MapSet.new([{0, 1}]),
      valuations: %{}
    }
  end

  test "recognizes supported model types and their logic" do
    assert Model.supported?(sdl_model())
    assert Model.supported?(ddl_model())
    refute Model.supported?(%{})

    assert Model.model_logic(sdl_model()) == :sdl
    assert Model.model_logic(ddl_model()) == :ddl
    assert Model.assert_supported!(sdl_model()) == sdl_model()

    assert_raise ArgumentError, ~r/unsupported countermodel/, fn ->
      apply(Model, :assert_supported!, [%{}])
    end
  end

  test "exposes logic-specific designated worlds and graph names" do
    assert Model.designated_world(sdl_model()) == 1
    assert Model.designated_world_constant(sdl_model()) == "actual_world"
    assert Model.graph_name(sdl_model()) == "KripkeModel"

    assert Model.designated_world(ddl_model()) == 0
    assert Model.designated_world_constant(ddl_model()) == "aw"
    assert Model.graph_name(ddl_model()) == "PreferenceModel"
  end

  test "computes worlds, edges, atoms, labels, and matrices" do
    model = sdl_model()

    assert Model.world_indices(model) == [0, 1, 2]
    assert Model.world_name(model, 0) == "i1"
    assert Model.world_name(model, 2) == "i3"
    assert Model.atom_names(model) == ["go", "tell"]
    assert Model.has_edge(model, 0, 1)
    refute Model.has_edge(model, 1, 0)
    assert Model.edge_count(model) == 3
    assert Model.self_loops(model) == MapSet.new([{0, 0}, {2, 2}])
    assert Model.proper_edges(model) == MapSet.new([{0, 1}])
    assert Model.label_for_world(model, 0) == "i1: go, ¬tell"
    assert Model.label_for_world(model, 1, ["go"]) == "i2: ¬go"

    assert Model.relation_matrix(model) == [
             [true, true, false],
             [false, false, false],
             [false, false, true]
           ]
  end

  test "builds logic-specific summaries" do
    assert Model.as_summary(sdl_model()) == %{
             source: "example.txt",
             kind: :countermodel,
             model_logic: :sdl,
             cardinality: 3,
             relation: "R",
             designated_world: "i2",
             edge_count: 3,
             atoms: ["go", "tell"],
             warnings: ["example warning"]
           }

    assert Model.as_summary(ddl_model()) == %{
             source: "<text>",
             kind: :model,
             model_logic: :ddl,
             cardinality: 2,
             relation: "R",
             designated_world: "i1",
             edge_count: 1,
             atoms: [],
             warnings: []
           }
  end

  test "builds a JSON-compatible export map" do
    assert Model.to_export_map(sdl_model()) == %{
             "logic" => "sdl",
             "kind" => "countermodel",
             "cardinality" => 3,
             "relation" => "R",
             "designated_world" => %{"index" => 1, "name" => "i2", "role" => "initial_world"},
             "edges" => [
               {0, 0},
               {0, 1},
               {2, 2}
             ],
             "atoms" => ["go", "tell"],
             "valuations" => %{
               "go" => [true, false, true],
               "tell" => [false, true, false]
             },
             "warnings" => ["example warning"],
             "worlds" => [
               %{
                 "index" => 0,
                 "name" => "i1"
               },
               %{
                 "index" => 1,
                 "name" => "i2"
               },
               %{
                 "index" => 2,
                 "name" => "i3"
               }
             ]
           }
  end

  test "exports the designated world for DDL models" do
    export = Model.to_export_map(ddl_model())

    assert export["logic"] == "ddl"
    assert export["kind"] == "model"
    assert export["designated_world"] == %{"index" => 0, "name" => "i1", "role" => "actual_world"}
    assert export["edges"] == [{0, 1}]
  end
end
