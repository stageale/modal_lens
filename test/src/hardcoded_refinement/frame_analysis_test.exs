defmodule Src.HardcodedRefinement.FrameAnalysisTest do
  use ExUnit.Case, async: true

  alias Src.HardcodedRefinement.FrameAnalysis
  alias Src.Core.Model

  describe "violations/2" do
    test "serial detects dead ends" do
      frame = [{:a, :b}]

      assert FrameAnalysis.violations(frame, :serial) == [:b]
      refute FrameAnalysis.check?(frame, :serial)
    end

    test "serial accepts frames where every world has a successor" do
      frame = [{:a, :b}, {:b, :b}]

      assert FrameAnalysis.violations(frame, :serial) == []
      assert FrameAnalysis.check?(frame, :serial)
    end

    test "reflexive detects missing loops" do
      frame = [{:a, :a}, {:a, :b}]

      assert FrameAnalysis.violations(frame, :reflexive) == [:b]
      refute FrameAnalysis.check?(frame, :reflexive)
    end

    test "transitive detects missing closure edges" do
      frame = [{:a, :b}, {:b, :c}]

      assert FrameAnalysis.violations(frame, :transitive) == [{:a, :b, :c}]
      refute FrameAnalysis.check?(frame, :transitive)
    end

    test "symmetric detects missing reverse edges" do
      frame = [{:a, :b}]

      assert FrameAnalysis.violations(frame, :symmetric) == [{:b, :a}]
      refute FrameAnalysis.check?(frame, :symmetric)
    end

    test "euclidean detects missing spans" do
      frame = [{:a, :b}, {:a, :c}]

      violations = FrameAnalysis.violations(frame, :euclidean)

      assert {:a, :b, :c} in violations
      assert {:a, :c, :b} in violations
      refute FrameAnalysis.check?(frame, :euclidean)
    end

    test "functional detects worlds with no successor" do
      frame = [{:a, :b}]

      assert FrameAnalysis.violations(frame, :functional) == [{:b, []}]
      refute FrameAnalysis.check?(frame, :functional)
    end

    test "total functional accepts exactly one successor per world" do
      frame = [{:a, :b}, {:b, :b}]

      assert FrameAnalysis.violations(frame, :functional) == []
      assert FrameAnalysis.check?(frame, :functional)
    end
  end

  describe "worlds_for_model/1" do
    test "builds zero-based worlds from model cardinality" do
      model = %Model{cardinality: 3}

      assert FrameAnalysis.worlds_for_model(model) == [0, 1, 2]
    end

    test "returns an empty world list for invalid cardinalities" do
      assert FrameAnalysis.worlds_for_model(%{cardinality: 0}) == []
      assert FrameAnalysis.worlds_for_model(%{cardinality: nil}) == []
      assert FrameAnalysis.worlds_for_model(%{}) == []
    end
  end

  describe "analysis_from_model/1 and analysis_from_model/2" do
    test "returns a FrameAnalysis struct" do
      model = %Model{
        cardinality: 2,
        edges: MapSet.new([{0, 1}])
      }

      assert %FrameAnalysis{} = FrameAnalysis.analysis_from_model(model)
    end

    test "detects frame violations using explicit worlds" do
      model = %Model{
        cardinality: 3,
        edges: MapSet.new([{0, 1}, {1, 2}])
      }

      analysis = FrameAnalysis.analysis_from_model(model, [0, 1, 2])

      assert %FrameAnalysis{} = analysis

      refute analysis.serial?
      refute analysis.reflexive?
      refute analysis.transitive?
      refute analysis.symmetric?
      refute analysis.euclidean?
      refute analysis.functional?

      assert analysis.dead_ends == [2]
      assert analysis.missing_loops == [0, 1, 2]
      assert {0, 1, 2} in analysis.missing_hulls

      assert {1, 0} in analysis.antisymmetries
      assert {2, 1} in analysis.antisymmetries

      assert {0, 1, 1} in analysis.missing_spans
      assert {1, 2, 2} in analysis.missing_spans

      assert MapSet.member?(analysis.function_violations, {2, []})
    end

    test "marks fully reflexive one-world frame as satisfying basic properties" do
      model = %Model{
        cardinality: 1,
        edges: MapSet.new([{0, 0}])
      }

      analysis = FrameAnalysis.analysis_from_model(model)

      assert analysis.serial?
      assert analysis.reflexive?
      assert analysis.transitive?
      assert analysis.symmetric?
      assert analysis.euclidean?
      assert analysis.functional?

      assert analysis.dead_ends == []
      assert analysis.missing_loops == []
      assert analysis.missing_hulls == []
      assert analysis.antisymmetries == []
      assert analysis.missing_spans == []
      assert MapSet.size(analysis.function_violations) == 0
    end
  end

  describe "frame_axiom/2" do
    test "emits frame axiom strings" do
      assert FrameAnalysis.frame_axiom("R", :serial) == "∀w. ∃v. R w v"
      assert FrameAnalysis.frame_axiom("R", :reflexive) == "∀w. R w w"
    end
  end
end
