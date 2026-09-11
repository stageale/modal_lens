Code.require_file("../../support/refinement_helpers.exs", __DIR__)

defmodule Src.Interface.RefinementCLITest do
  @moduledoc "Tests refine arguments, terminal decisions, report writing and final verbalization."
  use ExUnit.Case
  import ExUnit.CaptureIO
  alias Src.Interface.CLI
  alias Src.Refinement.TestSupport
  setup do: TestSupport.pipeline_context()

  test "rejects missing inputs and unknown switches", _context do
    assert capture_io(:stderr, fn -> assert CLI.main(["refine"]) == 2 end) =~ "one .thy file"

    assert capture_io(:stderr, fn -> assert CLI.main(["refine", "Base.thy", "--unknown"]) == 2 end) =~
             "Invalid refinement options"
  end

  test "automatic refinement writes its report under the requested output directory", context do
    capture_io(fn ->
      assert CLI.main(arguments(context) ++ ["--auto-refine", "--no-verbalize"]) == 0
    end)

    report = read_report(context)
    assert report["applied_refinement_count"] == 1
    assert report["stop_reason"] == "max_rounds"
    assert report["initial"]["output_dir"] == context.run.output_dir
    assert TestSupport.calls(context, "verbalization") == []
  end

  test "the default terminal decision declines an empty answer", context do
    output =
      capture_io("\n", fn ->
        assert CLI.main(arguments(context) ++ ["--no-verbalize"]) == 0
      end)

    assert output =~ "Apply this refinement axiom?"
    assert read_report(context)["stop_reason"] == "decision_stop"
    assert read_report(context)["applied_refinement_count"] == 0
  end

  test "the default terminal decision accepts yes", context do
    capture_io("yes\n", fn ->
      assert CLI.main(arguments(context) ++ ["--no-verbalize"]) == 0
    end)

    assert read_report(context)["applied_refinement_count"] == 1
  end

  test "verbalizes the completed report with the requested Ollama model", context do
    File.touch!(Path.join(context.root, "empty-models"))

    output =
      capture_io(fn ->
        assert CLI.main(
                 arguments(context) ++
                   [
                     "--verbalization-backend",
                     "ollama",
                     "--verbalization-model",
                     "qwen-fixture",
                     "--verbalization-mode",
                     "interpretive",
                     "--verbalization-reasoning",
                     "on",
                     "--verbalization-max-new-tokens",
                     "2048"
                   ]
               ) == 0
      end)

    assert [request_path] = TestSupport.calls(context, "verbalization")
    request = Jason.decode!(File.read!(request_path))
    assert request["backend"] == "ollama"
    assert request["model_id"] == "qwen-fixture"
    assert request["schema_version"] == "1.0"
    assert request["verbalization_mode"] == "interpretive"
    assert request["reasoning"] == true
    assert request["max_new_tokens"] == 2048
    assert request["report_path"] == Path.join(context.run.output_dir, "refinement.json")
    assert output =~ request["report_path"]
    assert read_report(context)["applied_refinement_count"] == 0

    for filename <- ["summary.json", "summary.md", "raw_output.txt", "provenance.json"] do
      path = Path.join(request["output_directory"], filename) |> Path.expand()
      assert File.regular?(path)
      assert output =~ path
    end
  end

  test "keeps the completed report when final verbalization fails", context do
    File.touch!(Path.join(context.root, "empty-models"))
    File.touch!(Path.join(context.root, "fail-verbalization"))

    capture_io(fn ->
      assert CLI.main(
               arguments(context) ++
                 [
                   "--verbalization-backend",
                   "ollama",
                   "--verbalization-model",
                   "qwen-fixture"
                 ]
             ) == 1
    end)

    assert read_report(context)["status"] == "completed"
    assert [_] = TestSupport.calls(context, "verbalization")
  end

  @spec arguments(map()) :: [String.t()]
  defp arguments(context) do
    [
      "refine",
      context.theory,
      "-o",
      context.run.output_dir,
      "--max-models",
      "1",
      "--max-refinement-rounds",
      "1",
      "--no-render-graph",
      "--atoms",
      "p,q"
    ]
  end

  @spec read_report(map()) :: map()
  defp read_report(context) do
    context.run.output_dir |> Path.join("refinement.json") |> File.read!() |> Jason.decode!()
  end
end
