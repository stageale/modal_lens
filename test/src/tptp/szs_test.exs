defmodule Src.TPTP.SZSTest do
  use ExUnit.Case, async: true

  alias Src.TPTP.SZS

  test "parses theorem and counter-satisfiable statuses" do
    assert {:ok, :theorem} =
             SZS.parse("% SZS status Theorem for demo.p")

    assert {:ok, :counter_satisfiable} =
             SZS.parse("% SZS status CounterSatisfiable for demo.p")
  end

  test "parses operational statuses without turning them into semantic results" do
    assert {:ok, :timeout} = SZS.parse("% SZS status Timeout for demo.p")
    assert {:ok, :gave_up} = SZS.parse("% SZS status GaveUp for demo.p")

    refute SZS.semantic_result?(:timeout)
    refute SZS.semantic_result?(:gave_up)
  end

  test "marks established semantic statuses as semantic results" do
    for status <- [
          :theorem,
          :counter_satisfiable,
          :satisfiable,
          :unsatisfiable,
          :contradictory_axioms
        ] do
      assert SZS.semantic_result?(status)
    end
  end

  test "rejects unsupported SZS statuses explicitly" do
    assert {:error, {:unsupported_status, "SomeFutureStatus"}} =
             SZS.parse("% SZS status SomeFutureStatus for demo.p")
  end

  test "returns an explicit error when no SZS status is present" do
    assert {:error, :status_not_found} = SZS.parse("ordinary prover output")
  end
end
