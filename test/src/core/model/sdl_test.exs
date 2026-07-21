defmodule Src.Core.Model.SDLTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.SDL

  test "provides Kripke-model defaults" do
    model = %SDL{cardinality: 2}

    assert model.cardinality == 2
    assert model.relation_name == nil
    assert model.initial_world == 0
    assert model.edges == MapSet.new()
    assert model.valuations == %{}
    assert model.warnings == []
    assert model.raw_text == ""
  end

  test "requires cardinality when constructed dynamically" do
    assert_raise ArgumentError, fn -> struct!(SDL, []) end
  end
end
