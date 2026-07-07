defmodule Src.Interface.ExperimentTest do
  use ExUnit.Case, async: true

  alias Src.HardcodedRefinement.FrameAnalysis
  alias Src.Interface.Experiment

  test "analyse_file/2 runs the vertical pipeline" do
    path = tmp_file("experiment_countermodel.txt", nitpick_with_atoms())

    entry = Experiment.analyse_file(path, atoms: "go,tell")

    assert entry.file == path
    assert entry.model.cardinality == 2
    assert entry.worlds == [0, 1]
    assert %FrameAnalysis{} = entry.analysis

    assert Map.has_key?(entry.model.valuations, "go")
    assert Map.has_key?(entry.model.valuations, "tell")

    assert is_list(entry.suggestions)
    assert length(entry.suggestions) > 0

    assert is_list(entry.explanations)
    assert length(entry.explanations) > 0
  end

  test "summary_file/2 builds compact summary from the shared pipeline" do
    path = tmp_file("summary_countermodel.txt", nitpick_with_atoms())

    summary = Experiment.summary_file(path, atoms: "go,tell")

    assert summary.file == path
    assert summary.source == path
    assert summary.kind == :countermodel
    assert summary.cardinality == 2
    assert summary.relation == "R"
    assert summary.initial_world == "i1"
    assert summary.edge_count == 2
    assert summary.atoms == ["go", "tell"]
    assert summary.worlds == [0, 1]

    assert %FrameAnalysis{} = summary.analysis
    assert summary.suggestion_count == length(summary.suggestions)
    assert summary.explanation_count > 0
    assert summary.best_axiom != nil
    assert is_float(summary.best_score)
  end

  test "rank_files/2 aggregates axiom suggestions across files" do
    first = tmp_file("rank_first.txt", nitpick_with_atoms())
    second = tmp_file("rank_second.txt", nitpick_with_atoms())

    result =
      Experiment.rank_files([first, second],
        atoms: "go,tell",
        limit: 3
      )

    assert result.input_count == 2
    assert result.inputs == [first, second]
    assert length(result.models) == 2
    assert length(result.ranked_axioms) == 3

    assert Enum.all?(result.ranked_axioms, fn row ->
             is_atom(row.axiom) and
               is_number(row.score) and
               is_integer(row.violations) and
               is_integer(row.support) and
               is_integer(row.affected_models) and
               is_list(row.models)
           end)
  end

  test "rank_files/2 accepts a single path as direct API input" do
    path = tmp_file("single_rank.txt", nitpick_with_atoms())

    result = Experiment.rank_files(path, atoms: "go,tell", limit: 1)

    assert result.input_count == 1
    assert result.inputs == [path]
    assert length(result.ranked_axioms) == 1
  end

  defp tmp_file(filename, content) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_experiment_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    path = Path.join(dir, filename)
    File.write!(path, content)
    path
  end

  defp nitpick_with_atoms do
    """
    Nitpick found a counterexample for card i = 2:
      Constants:
        go =
          (λx. _)
          (i⇩1 := True, i⇩2 := False)
        tell =
          (λx. _)
          (i⇩1 := False, i⇩2 := True)
        (R) =
          (λx. _)
          ((i⇩1, i⇩1) := True, (i⇩1, i⇩2) := True,
           (i⇩2, i⇩1) := False, (i⇩2, i⇩2) := False)
        w = i⇩1
    """
  end
end
