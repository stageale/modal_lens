defmodule Src.Core.ParserTest do
  use ExUnit.Case

  alias Src.Core.Parser

  test "parses basic Nitpick countermodel metadata" do
    text = """
    Nitpick found a counterexample for card i = 6:DSS

    w = i⇩1
    """

    model = Parser.parse_nitpick_text(text)

    assert model.kind == :countermodel
    assert model.cardinality == 6
    assert model.initial_world == 0
    assert model.edges == MapSet.new()
    assert length(model.warnings) == 1
  end

  test "parses flat true relation edges" do
    text = """
    Nitpick found a counterexample for card i = 2:

    w = i⇩1
    R =
      (i⇩1, i⇩1) := True
      (i⇩1, i⇩2) := False
      (i⇩2, i⇩1) := True
      (i⇩2, i⇩2) := False
    """

    model = Parser.parse_nitpick_text(text)
    assert model.edges == MapSet.new([{0, 0}, {1, 0}])
  end

  @complex_nitpick_output """
  Nitpicking formula...
  Nitpick found a counterexample for card i = 6:
    Constants:
      go = (λx. _)
           (i⇩1 := False, i⇩2 := False, i⇩3 := False, i⇩4 := False,
              i⇩5 := True, i⇩6 := True)
      tell =
        (λx. _)
        (i⇩1 := False, i⇩2 := False, i⇩3 := False, i⇩4 := True,
           i⇩5 := False, i⇩6 := True)
      (R) =
        (λx. _)
        ((i⇩1, i⇩1) := False, (i⇩1, i⇩2) := False, (i⇩1, i⇩3) := False,
           (i⇩1, i⇩4) := False, (i⇩1, i⇩5) := True, (i⇩1, i⇩6) := True,
           (i⇩2, i⇩1) := True, (i⇩2, i⇩2) := True, (i⇩2, i⇩3) := False,
           (i⇩2, i⇩4) := True, (i⇩2, i⇩5) := False, (i⇩2, i⇩6) := False,
           (i⇩3, i⇩1) := False, (i⇩3, i⇩2) := True, (i⇩3, i⇩3) := False,
           (i⇩3, i⇩4) := False, (i⇩3, i⇩5) := False, (i⇩3, i⇩6) := False,
           (i⇩4, i⇩1) := False, (i⇩4, i⇩2) := True, (i⇩4, i⇩3) := True,
           (i⇩4, i⇩4) := False, (i⇩4, i⇩5) := False, (i⇩4, i⇩6) := False,
           (i⇩5, i⇩1) := False, (i⇩5, i⇩2) := True, (i⇩5, i⇩3) := True,
           (i⇩5, i⇩4) := True, (i⇩5, i⇩5) := False, (i⇩5, i⇩6) := False,
           (i⇩6, i⇩1) := False, (i⇩6, i⇩2) := True, (i⇩6, i⇩3) := True,
           (i⇩6, i⇩4) := True, (i⇩6, i⇩5) := True, (i⇩6, i⇩6) := False)
      aw = i⇩3
  """

  test "parses complex Nitpick countermodel with aw, atoms, and parenthesized R" do
    model =
      Parser.parse_nitpick_text(@complex_nitpick_output,
        relation: "R",
        atoms: ["go", "tell"]
      )

    assert model.kind == :countermodel
    assert model.cardinality == 6
    assert model.initial_world == 2

    assert model.valuations["go"] == [
             false,
             false,
             false,
             false,
             true,
             true
           ]

    assert model.valuations["tell"] == [
             false,
             false,
             false,
             true,
             false,
             true
           ]

    expected_edges =
      MapSet.new([
        {0, 4},
        {0, 5},
        {1, 0},
        {1, 1},
        {1, 3},
        {2, 1},
        {3, 1},
        {3, 2},
        {4, 1},
        {4, 2},
        {4, 3},
        {5, 1},
        {5, 2},
        {5, 3},
        {5, 4}
      ])

    assert model.edges == expected_edges
    assert MapSet.size(model.edges) == 15
    assert model.warnings == []
  end
end
