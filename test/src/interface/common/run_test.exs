defmodule Src.Interface.Common.RunTest do
  use ExUnit.Case, async: true

  alias Src.Interface.Common.Run

  test "tracks a completed run" do
    assert {:ok, run} =
             Run.new(
               "run-1",
               "/tmp/run-1",
               %{palette: :turbo}
             )

    assert {:ok, run} = Run.start(run)
    assert {:ok, run} = Run.put_artifact(run, :report_json, "report.json")
    assert {:ok, run} = Run.put_metric(run, :duration_ms, 12)
    assert {:ok, run} = Run.complete(run)

    data = Run.to_map(run)

    assert data["status"] == "completed"
    assert data["params"]["palette"] == "turbo"
    assert data["artifacts"]["report_json"] == "report.json"
    assert data["metrics"]["duration_ms"] == 12
  end
end
