defmodule Src.SerializationTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.SDL
  alias Src.Core.ParseWarning
  alias Src.Serialization

  test "converts nested Elixir values into deterministic JSON-compatible data" do
    value = %{
      status: :completed,
      tuple: {:a, 1},
      set: MapSet.new([3, 1, 2]),
      warning: %ParseWarning{message: "warning"}
    }

    assert Serialization.safe(value) == %{
             "status" => "completed",
             "tuple" => ["a", 1],
             "set" => [1, 2, 3],
             "warning" => %{"message" => "warning"}
           }
  end

  test "exports supported model structs through the model contract" do
    model = %SDL{
      kind: :countermodel,
      cardinality: 1,
      relation_name: "R",
      initial_world: 0,
      edges: MapSet.new([{0, 0}]),
      valuations: %{"p" => [true]}
    }

    export = Serialization.safe(model)
    assert export["logic"] == "sdl"
    assert export["edges"] == [[0, 0]]
    assert export["valuations"] == %{"p" => [true]}
  end
end
