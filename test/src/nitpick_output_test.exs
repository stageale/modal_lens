defmodule Src.NitpickOutputTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.DDL
  alias Src.NitpickOutput

  @nitpick_output """
  Nitpick found a counterexample for card i = 2:
  aw = i⇩2
  R =
    (i⇩1, i⇩1) := False
    (i⇩1, i⇩2) := True
    (i⇩2, i⇩1) := False
    (i⇩2, i⇩2) := False
  go = (λx. _)
    (i⇩1 := True, i⇩2 := False)
  """

  test "parses stored Nitpick output with normalized atom options" do
    path = tmp_file("stored.txt", @nitpick_output)

    model =
      NitpickOutput.parse_nitpick_file(path,
        model_logic: :ddl,
        atoms: "go"
      )

    assert %DDL{} = model
    assert model.actual_world == 1
    assert model.valuations["go"] == [true, false]
  end

  test "returns a compact summary for a stored result" do
    path = tmp_file("summary.txt", @nitpick_output)

    summary =
      NitpickOutput.summary_file(path,
        model_logic: :ddl,
        atoms: ["go"]
      )

    assert summary.file == Path.expand(path)
    assert summary.source == path
    assert summary.model_logic == :ddl
    assert summary.actual_world == "i2"
    assert summary.worlds == [0, 1]
    assert summary.warning_count == 0
  end

  test "analyses a stored file and can include the designated world" do
    path = tmp_file("analysis.txt", @nitpick_output)

    result =
      NitpickOutput.analyse_file(path,
        model_logic: :ddl,
        atoms: "go",
        blocking_name: "stored_model",
        include_atoms: true,
        include_designated_world: true,
        designated_world_constant: "aw"
      )

    assert result.status == :parsed_countermodel
    assert result.file == Path.expand(path)
    assert result.worlds == [0, 1]
    assert result.blocking_axiom =~ "ax_stored_model:"
    assert result.blocking_axiom =~ "(aw = u2)"
    assert result.llm_explanation == nil
  end

  defp tmp_file(name, content) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_nitpick_output_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end
end
