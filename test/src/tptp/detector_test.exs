defmodule Src.TPTP.DetectorTest do
  use ExUnit.Case, async: true

  alias Src.TPTP.Detector

  test "detects supported TPTP top-level constructs" do
    assert Detector.detect("thf(a,axiom,$true).") == :thf
    assert Detector.detect("   include('Axioms/base.ax').") == :include
  end

  test "returns unknown for unsupported constructs" do
    assert Detector.detect("fof(a,axiom,$true).") == :unknown
  end
end
