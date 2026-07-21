defmodule Src.Interface.CLITest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Src.Interface.CLI

  test "prints usage for an empty argument list" do
    output =
      capture_io(fn ->
        assert CLI.main([]) == 0
      end)

    assert output =~ "Usage:"
    assert output =~ "axiom_refiner enumerate"
  end

  test "reports commands that are intentionally unavailable" do
    output =
      capture_io(:stderr, fn ->
        assert CLI.main(["rank"]) == 1
      end)

    assert output =~ "deprecated axiom-scoring pipeline"
  end

  test "rejects an unknown enumeration mode before running Isabelle" do
    output =
      capture_io(:stderr, fn ->
        assert CLI.main(["enumerate", "--mode", "unknown"]) == 2
      end)

    assert output =~ "Unknown mode"
  end

  test "requires inputs for the summary command" do
    output =
      capture_io(:stderr, fn ->
        assert CLI.main(["summary"]) == 1
      end)

    assert output =~ "No input files given"
  end
end
