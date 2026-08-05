defmodule Src.Core.ParserTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.DDL
  alias Src.Core.Model.SDL
  alias Src.Core.Parser

  @nitpick_output """
  Nitpick found a counterexample for card i = 2:

  aw = i⇩2
  R =
    (i⇩1, i⇩1) := False
    (i⇩1, i⇩2) := True
    (i⇩2, i⇩1) := False
    (i⇩2, i⇩2) := True
  go = (λx. _)
    (i⇩1 := True, i⇩2 := False)
  tell = (λx. _)
    (i⇩1 := False, i⇩2 := True)
  """

  test "exposes reusable assignment regexes" do
    assert Regex.match?(Parser.world_pair_regex(), "(i⇩1, i⇩2) := True")
    assert Regex.match?(Parser.bool_assign_regex(), "i⇩2 := False")
  end

  test "parses an SDL countermodel" do
    model =
      Parser.parse_nitpick_text(@nitpick_output,
        relation: "R",
        atoms: ["go", "tell"]
      )

    assert %SDL{} = model
    assert model.kind == :countermodel
    assert model.cardinality == 2
    assert model.initial_world == 1
    assert model.edges == MapSet.new([{0, 1}, {1, 1}])

    assert model.valuations == %{
             "go" => [true, false],
             "tell" => [false, true]
           }

    assert model.warnings == []
  end

  test "parses a DDL model and detects atoms automatically" do
    text = String.replace(@nitpick_output, "counterexample", "model")

    model =
      Parser.parse_nitpick_text(text,
        model_logic: :ddl,
        relation: "R",
        auto_atoms: true
      )

    assert %DDL{} = model
    assert model.kind == :model
    assert model.actual_world == 1
    assert model.valuations["go"] == [true, false]
    assert model.valuations["tell"] == [false, true]
  end

  test "adds warnings for absent designated worlds, edges, and requested atoms" do
    model =
      Parser.parse_nitpick_text(
        "Nitpick found a counterexample for card i = 1:",
        atoms: ["missing"]
      )

    messages = Enum.map(model.warnings, & &1.message)

    assert "No explicit designated world found; defaulted to i1." in messages
    assert "No true edges found for relation 'R'." in messages
    assert "Atom 'missing' not found; omitted." in messages
  end

  test "parses a file and records its source path" do
    path = tmp_file("nitpick.txt", @nitpick_output)
    model = Parser.parse_nitpick_file(path, atoms: ["go"])

    assert model.source == path
    assert model.raw_text == @nitpick_output
  end

  test "rejects no-result text and unsupported model logic" do
    assert_raise ArgumentError, ~r/no counterexample/, fn ->
      Parser.parse_nitpick_text("Nitpick found no counterexample")
    end

    assert_raise ArgumentError, ~r/unsupported model logic/, fn ->
      Parser.parse_nitpick_text(@nitpick_output, model_logic: :unknown)
    end
  end

  defp tmp_file(name, content) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_parser_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end
end
