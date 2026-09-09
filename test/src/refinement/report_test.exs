Code.require_file("../../support/refinement_helpers.exs", __DIR__)

defmodule Src.Refinement.ReportTest do
  @moduledoc "Tests recorded axioms, round provenance and bounded enumeration observations."
  use ExUnit.Case, async: true
  alias Src.Execution.Run
  alias Src.Refinement.{Iteration, Loop, Report, TestSupport}
  setup do: TestSupport.workspace()

  test "records initial and final state without applied rounds", context do
    loop = example_loop(context, 0)
    report = Report.to_map(loop)
    assert report["schema"] == "modal-lens/refinement-report"
    assert report["schema_version"] == "1.0"
    assert report["status"] == "completed"
    assert report["stop_reason"] == "no_refinement_candidate"
    assert report["applied_refinement_count"] == 0
    assert report["iteration"] == []
    assert report["initial"] == report["final"]
    assert report["initial"]["enumeration"] == %{"status" => "exhausted", "model_count" => 0}
  end

  test "chains complete before and after observations across rounds", context do
    report = Report.to_map(example_loop(context, 2))
    assert [first, second] = report["iteration"]
    assert report["applied_refinement_count"] == 2
    assert report["stop_reason"] == "max_rounds"
    assert first["enumeration_before"] == report["initial"]["enumeration"]
    assert first["enumeration_before"] == %{"status" => "max_models_reached", "model_count" => 2}
    assert first["enumeration_after"] == %{"status" => "max_models_reached", "model_count" => 2}
    assert second["enumeration_before"] == first["enumeration_after"]
    assert second["enumeration_after"] == report["final"]["enumeration"]
    assert second["enumeration_after"] == %{"status" => "exhausted", "model_count" => 0}
    refute Jason.encode!(report) =~ "model_count_delta"
  end

  test "uses actually applied candidates and written axioms despite recurring IDs", context do
    loop = example_loop(context, 2)
    [first, second] = Report.to_map(loop)["iteration"]
    for {entry, iteration} <- Enum.zip([first, second], loop.iterations) do
      assert entry["candidate"] == iteration.selected_candidate
      assert entry["candidate_id"] == iteration.selected_candidate["candidate_id"]
      assert entry["cluster_support"] == iteration.selected_candidate["origin"]["cluster_support"]
      assert entry["outside_support"] == iteration.selected_candidate["origin"]["outside_support"]
      assert entry["graphlet_size"] == 2
      assert entry["refinement_axiom"] == iteration.refined_theory.refinement_axiom
    end
    assert first["pattern_id"] == second["pattern_id"]
    assert first["cluster_id"] == second["cluster_id"]
    assert first["run_id"] != second["run_id"]
    assert first["refinement_axiom"] != second["refinement_axiom"]
    assert second["input_theory_path"] == first["refined_theory_path"]
  end

  test "writes to the initial run and supports an explicit output path", context do
    loop = example_loop(context, 2)
    assert {:ok, default} = Report.write(loop)
    assert default == Path.join(loop.initial_run.output_dir, "refinement.json")
    assert Jason.decode!(File.read!(default)) == Report.to_map(loop)
    custom = Path.join(context.root, "exports/custom.json")
    assert {:ok, ^custom} = Report.write(loop, custom)
    assert File.read!(custom) == File.read!(default)
  end

  @spec example_loop(map(), 0 | 2) :: Loop.t()
  defp example_loop(context, rounds) do
    {:ok, initial} = Run.new("initial", Path.join(context.root, "initial"))
    initial = %{initial | status: :completed}
    initial_result = if rounds == 0, do: %{status: :exhausted, model_count: 0},
      else: %{status: :max_models_reached, model_count: 2}

    {iterations, final_theory, final_run, final_result} =
      Enum.reduce(if(rounds == 0, do: [], else: 1..rounds), {[], context.theory, initial, initial_result},
        fn round, {iterations, base, _run, _result} ->
          {:ok, run} = Run.new("round-#{round}", Path.join(context.root, "round-#{round}"))
          run = %{run | status: :completed}
          candidate = TestSupport.candidate(cluster_support: if(round == 1, do: 0.75, else: 0.5))
          theory = Path.join(run.output_dir, "Refined#{round}.thy")
          result = if round == 1, do: %{status: :max_models_reached, model_count: 2},
            else: %{status: :exhausted, model_count: 0}
          iteration = %Iteration{
            round: round, input_theory_path: base, selected_candidate: candidate,
            refined_theory: %{theory_path: theory,
              refinement_axiom: "axiomatization where ax_written_#{round}: \"True\""},
            run: run, pipeline_result: result
          }
          {iterations ++ [iteration], theory, run, result}
        end)

    %Loop{
      initial_theory_path: context.theory, initial_run: initial, initial_pipeline_result: initial_result,
      iterations: iterations, final_theory_path: final_theory, final_run: final_run,
      final_pipeline_result: final_result,
      stop_reason: if(rounds == 0, do: :no_refinement_candidate, else: :max_rounds)
    }
  end
end
