defmodule Src.Interface.ExperimentTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.DDL
  alias Src.Interface.Experiment

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
      Experiment.parse_nitpick_file(path,
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
      Experiment.summary_file(path,
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

  test "analyses a stored file without invoking Isabelle" do
    path = tmp_file("analysis.txt", @nitpick_output)

    result =
      Experiment.analyse_file(path,
        model_logic: :ddl,
        atoms: "go",
        blocking_name: "stored_model"
      )

    expected_blocking_axiom =
      ~S"""
      axiomatization where
        ax_stored_model: "\<not>(
            \<exists>u1 u2.
            distinct [u1, u2] \<and>
            (\<forall>x. x = u1 \<or> x = u2) \<and>
            \<not>(R u1 u1) \<and>
            (R u1 u2) \<and>
            \<not>(R u2 u1) \<and>
            \<not>(R u2 u2) \<and>
            (go u1) \<and>
            \<not>(go u2)
        )"
      """
      |> String.trim()

    assert result.status == :parsed_countermodel
    assert result.file == Path.expand(path)
    assert result.worlds == [0, 1]
    assert result.blocking_axiom == expected_blocking_axiom
   assert result.llm_explanation == nil
  end

  test "returns a validation error for a missing theory" do
    missing = Path.join(System.tmp_dir!(), "missing_#{System.unique_integer([:positive])}.thy")

    assert {:error, {:theory_not_found, expanded}} =
             Experiment.analyse_theory(missing, output_dir: tmp_dir("output"))

    assert expanded == Path.expand(missing)
  end

  defp tmp_file(name, content) do
    dir = tmp_dir("files")
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  defp tmp_dir(label) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_experiment_#{label}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
