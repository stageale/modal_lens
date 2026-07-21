defmodule Src.Core.Model.DDLTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.DDL

  test "provides preference-model defaults" do
    model = %DDL{cardinality: 2}

    assert model.cardinality == 2
    assert model.relation_name == "R"
    assert model.actual_world == 0
    assert model.edges == MapSet.new()
    assert model.valuations == %{}
    assert model.warnings == []
    assert model.raw_text == ""
  end

  test "requires cardinality when constructed dynamically" do
    assert_raise ArgumentError, fn -> struct!(DDL, []) end
  end
end
