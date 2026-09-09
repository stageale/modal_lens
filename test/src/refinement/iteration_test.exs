Code.require_file("../../support/refinement_helpers.exs", __DIR__)

defmodule Src.Refinement.IterationTest do
  @moduledoc "Exercises a refinement iteration through the real pipeline and synthetic backends."
  use ExUnit.Case
  alias Src.Execution.ArtifactStore
  alias Src.Refinement.{Iteration, TestSupport}
  setup do: TestSupport.pipeline_context()

  test "applies a candidate, registers its theory and runs the pipeline once", context do
    applied = TestSupport.candidate(cluster_support: 0.6, outside_support: 0.4)
    next = TestSupport.candidate(id: "next-candidate")
    TestSupport.write_candidates(context, [next])
    assert {:ok, result} = Iteration.run(context.run, context.theory, applied, round: 3)
    assert result.round == 3
    assert result.selected_candidate == applied
    assert result.input_theory_path == context.theory
    assert result.run.status == :completed
    assert result.pipeline_result.selected_refinement_candidate == next
    assert result.pipeline_result.status == :max_models_reached
    assert TestSupport.calls(context, "graph") == [result.refined_theory.theory_path]
    assert {:ok, manifest} = ArtifactStore.read_manifest(result.run)
    assert Map.has_key?(manifest["artifacts"], "refinement_theory")
    assert File.read!(result.refined_theory.theory_path) =~ result.refined_theory.refinement_axiom
  end

  test "preserves an exhausted zero-model observation", context do
    File.touch!(Path.join(context.root, "empty-models"))
    assert {:ok, result} = Iteration.run(context.run, context.theory, TestSupport.candidate())
    assert result.pipeline_result.status == :exhausted
    assert result.pipeline_result.model_count == 0
    assert result.pipeline_result.selected_refinement_candidate == nil
    assert TestSupport.calls(context, "graph") == []
  end

  test "wraps theory generation failures before invoking backends", context do
    missing = Path.join(context.root, "Missing.thy")
    assert {:error, {:refinement_theory_failed, {:base_theory_not_found, ^missing}}, run} =
      Iteration.run(context.run, missing, TestSupport.candidate())
    assert run.status == :planned
    assert TestSupport.calls(context, "isabelle") == []
  end

  test "wraps a refined pipeline failure and retains the written theory", context do
    File.touch!(Path.join(context.root, "fail-isabelle"))
    assert {:error, {:refined_pipeline_failed, _reason}, run} =
      Iteration.run(context.run, context.theory, TestSupport.candidate())
    assert run.status == :failed
    assert [_] = Path.wildcard(Path.join(context.run.output_dir, "refinement_theory/*.thy"))
  end
end
