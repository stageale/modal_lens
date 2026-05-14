defmodule Src.Refinement.FrameAnalysisTest do
  use ExUnit.Case, async: true

  alias Src.Refinement.FrameAnalysis

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

      assert FrameAnalysis.violations(frame, :symmetric) == [{:a, :b}]
      refute FrameAnalysis.check?(frame, :symmetric)
    end

    test "euclidean detects missing spans" do
      frame = [{:a, :b}, {:a, :c}]

      violations = FrameAnalysis.violations(frame, :euclidean)

      assert {:a, :b, :c} in violations
      assert {:a, :c, :b} in violations
      refute FrameAnalysis.check?(frame, :euclidean)
    end

    test "functional detects multiple successors" do
      frame = [{:a, :b}, {:a, :c}]

      violations = FrameAnalysis.violations(frame, :functional)

      assert {:a, :b, :c} in violations
      assert {:a, :c, :b} in violations
      refute FrameAnalysis.check?(frame, :functional)
    end

    test "total functional detects worlds with no successor" do
      frame = [{:a, :b}]

      assert FrameAnalysis.violations(frame, :total_functional) == [{:b, []}]
      refute FrameAnalysis.check?(frame, :total_functional)
    end

    test "total functional accepts exactly one successor per world" do
      frame = [{:a, :b}, {:b, :b}]

      assert FrameAnalysis.violations(frame, :total_functional) == []
      assert FrameAnalysis.check?(frame, :total_functional)
    end
  end

  describe "frame_axiom/2" do
    test "emits frame axiom strings" do
      assert FrameAnalysis.frame_axiom("R", :serial) == "∀w. ∃v. R w v"
      assert FrameAnalysis.frame_axiom("R", :reflexive) == "∀w. R w w"
    end
  end
end
