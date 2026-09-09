Code.require_file("../../support/refinement_helpers.exs", __DIR__)

defmodule Src.Execution.RefinementPipelineTest do
  @moduledoc "Checks that a pipeline run selects structural candidates without applying them."
  use ExUnit.Case
  alias Src.Execution.Pipeline
  alias Src.Refinement.{Axiom, TestSupport}
  setup do: TestSupport.pipeline_context()

  test "selects the best candidate without starting an outer refinement round", context do
    original = File.read!(context.theory)
    preferred = TestSupport.candidate(id: "preferred", cluster_support: 0.8, outside_support: 0.4)
    other = TestSupport.candidate(id: "other", cluster_support: 0.7, outside_support: 0.0)
    TestSupport.write_candidates(context, [other, preferred])
    assert {:ok, run, result} = Pipeline.run_theory(context.run, context.theory)
    assert run.status == :completed
    assert result.selected_refinement_candidate == preferred
    assert result.selected_refinement_axiom == Axiom.refinement_axiom(preferred)
    assert result.refinement_candidates == [other, preferred]
    assert TestSupport.calls(context, "graph") == [context.theory]
    assert File.read!(context.theory) == original
    assert Path.wildcard(Path.join(context.root, "**/*Refined*.thy")) == []
  end

  test "returns no selection when analyzed models have no candidates", context do
    TestSupport.write_candidates(context, [])
    assert {:ok, _, result} = Pipeline.run_theory(context.run, context.theory)
    assert result.model_count == 1
    assert result.refinement_candidates == []
    assert result.selected_refinement_candidate == nil
    assert result.selected_refinement_axiom == nil
  end

  test "reports an invalid selected axiom instead of applying or dropping it", context do
    invalid = put_in(TestSupport.candidate(), ["occurrence", "relation_cells"], [])
    TestSupport.write_candidates(context, [invalid])

    assert {:error, {:refinement_selection_failed, {:refinement_axiom_rendering_failed, _}}, run} =
             Pipeline.run_theory(context.run, context.theory)

    assert run.status == :failed
    assert Path.wildcard(Path.join(context.root, "**/*Refined*.thy")) == []
  end
end
