defmodule Src.Interface.CLITest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Src.Interface.CLI

  test "prints usage for an empty argument list" do
    output = capture_io(fn -> assert CLI.main([]) == 0 end)

    assert output =~ "Usage:"
    assert output =~ "axiom_refiner demo"
    assert output =~ "--no-render-graph"
    assert output =~ "--no-verbalize"
    assert output =~ "--no-auto-atoms"
  end

  test "reports removed and unknown commands uniformly" do
    output = capture_io(:stderr, fn -> assert CLI.main(["rank"]) == 1 end)
    assert output =~ "Unknown command: rank"
  end

  test "rejects missing and unknown enumeration modes before Isabelle" do
    missing =
      capture_io(:stderr, fn ->
        assert CLI.main(["enumerate"]) == 2
      end)

    assert missing =~ "Missing --mode"

    unknown =
      capture_io(:stderr, fn ->
        assert CLI.main(["enumerate", "--mode", "unknown"]) == 2
      end)

    assert unknown =~ "Unknown mode"
  end

  test "requires inputs for summary and exactly one theory for demo" do
    summary = capture_io(:stderr, fn -> assert CLI.main(["summary"]) == 1 end)
    assert summary =~ "No input files given"

    demo = capture_io(:stderr, fn -> assert CLI.main(["demo"]) == 2 end)
    assert demo =~ "requires one .thy file"
  end

  test "rejects invalid demo switches" do
    output =
      capture_io(:stderr, fn ->
        assert CLI.main(["demo", "Example.thy", "--unknown"]) == 2
      end)

    assert output =~ "Invalid demo options"
  end
end
