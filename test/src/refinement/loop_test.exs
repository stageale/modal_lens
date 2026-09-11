Code.require_file("../../support/refinement_helpers.exs", __DIR__)

defmodule Src.Refinement.LoopTest do
  @moduledoc "Tests the outer loop, explicit decisions and cumulative refinement runs."
  use ExUnit.Case
  alias Src.Refinement.{Loop, TestSupport}
  setup do: TestSupport.pipeline_context()

  test "zero rounds runs the initial pipeline without requesting a decision", context do
    decision = fn _, _, _ -> flunk("No refinement decision should be requested") end
    assert {:ok, loop} = Loop.run(context.run, context.theory, max_rounds: 0, decision: decision)
    assert loop.stop_reason == :max_rounds
    assert loop.iterations == []
    assert loop.final_theory_path == context.theory
    assert TestSupport.calls(context, "graph") == [context.theory]
  end

  test "automatic mode applies two rounds to the previously refined theory", context do
    assert {:ok, loop} =
             Loop.run(context.run, context.theory, max_rounds: 2, decision: :automatic)

    assert [first, second] = loop.iterations
    assert {first.round, second.round} == {1, 2}
    assert first.input_theory_path == context.theory
    assert second.input_theory_path == first.refined_theory.theory_path
    assert loop.final_theory_path == second.refined_theory.theory_path
    assert loop.final_run == second.run
    assert loop.stop_reason == :max_rounds
    assert first.run.id != second.run.id
    assert first.run.output_dir != second.run.output_dir

    assert TestSupport.calls(context, "graph") == [
             context.theory,
             first.refined_theory.theory_path,
             second.refined_theory.theory_path
           ]
  end

  test "a callback receives the candidate and current pipeline result", context do
    parent = self()

    decision = fn round, candidate, result ->
      send(parent, {:decision, round, candidate, result})
      if round == 1, do: :apply, else: :stop
    end

    assert {:ok, loop} = Loop.run(context.run, context.theory, max_rounds: 3, decision: decision)
    assert [iteration] = loop.iterations
    assert loop.stop_reason == :decision_stop
    assert_receive {:decision, 1, first_candidate, first_result}
    assert first_candidate == first_result.selected_refinement_candidate
    assert first_result == loop.initial_pipeline_result
    assert_receive {:decision, 2, next_candidate, next_result}
    assert next_candidate == next_result.selected_refinement_candidate
    assert next_result == iteration.pipeline_result
    refute_receive {:decision, 3, _, _}, 0
    assert length(TestSupport.calls(context, "graph")) == 2
  end

  test "stops before writing a refinement when the decision is stop", context do
    assert {:ok, loop} = Loop.run(context.run, context.theory, decision: fn _, _, _ -> :stop end)
    assert loop.stop_reason == :decision_stop
    assert loop.iterations == []
    refute File.exists?(Path.join(context.run.output_dir, "refinement"))
  end

  test "stops when no candidate remains after refinement", context do
    File.touch!(Path.join(context.root, "empty-refined"))
    assert {:ok, loop} = Loop.run(context.run, context.theory, max_rounds: 3)
    assert [_] = loop.iterations
    assert loop.stop_reason == :no_refinement_candidate
    assert loop.final_pipeline_result.status == :exhausted
    assert loop.final_pipeline_result.model_count == 0
  end

  test "reports invalid callback results without applying the candidate", context do
    assert {:error, {:invalid_decision, :unexpected}, run} =
             Loop.run(context.run, context.theory, decision: fn _, _, _ -> :unexpected end)

    assert run.status == :completed
    assert TestSupport.calls(context, "graph") == [context.theory]
  end

  test "rejects invalid options before starting the pipeline", context do
    assert {:error, {:invalid_max_rounds, -1}, _} =
             Loop.run(context.run, context.theory, max_rounds: -1)

    assert {:error, {:invalid_decision, :unknown}, _} =
             Loop.run(context.run, context.theory, decision: :unknown)

    assert TestSupport.calls(context, "isabelle") == []
  end

  test "wraps an initial pipeline failure", context do
    File.touch!(Path.join(context.root, "fail-isabelle"))

    assert {:error, {:initial_pipeline_failed, _reason}, run} =
             Loop.run(context.run, context.theory)

    assert run.status == :failed
  end
end
