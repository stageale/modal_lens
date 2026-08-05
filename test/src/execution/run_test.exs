defmodule Src.Execution.RunTest do
  use ExUnit.Case, async: true

  alias Src.Execution.Run

  test "tracks a complete run lifecycle" do
    assert {:ok, run} = Run.new(" run-1 ", "/tmp/run-1", %{palette: :turbo})
    assert run.id == "run-1"
    assert run.status == :planned

    assert {:ok, run} = Run.start(run)
    assert {:ok, run} = Run.put_artifact(run, :report_json, "report.json")
    assert {:ok, run} = Run.put_provenance(run, :backend, :local)
    assert {:ok, run} = Run.put_metric(run, :duration_ms, 12)
    assert {:ok, run} = Run.complete(run)

    assert {:ok, "report.json"} = Run.fetch_artifact(run, "report_json")

    data = Run.to_map(run)
    assert data["schema_version"] == "1.0"
    assert data["status"] == "completed"
    assert data["params"]["palette"] == "turbo"
    assert data["artifacts"]["report_json"] == "report.json"
    assert data["provenance"]["backend"] == "local"
    assert data["metrics"]["duration_ms"] == 12
    assert data["error"] == nil
  end

  test "rejects invalid transitions and missing failure reasons" do
    assert {:ok, run} = Run.new("run", "/tmp/run")

    assert {:error, {:invalid_status_transition, :planned, :completed}} =
             Run.complete(run)

    assert {:error, :missing_failure_reason} = Run.fail(run, nil)

    assert {:ok, failed} = Run.fail(run, :boom)
    assert failed.status == :failed
    assert failed.error == :boom

    assert {:error, {:invalid_status_transition, :failed, :running}} =
             Run.start(failed)
  end

  test "normalizes names and rejects absent values" do
    assert {:ok, run} = Run.new("run", "/tmp/run")
    assert {:ok, run} = Run.put_artifact(run, " report ", "report.json")
    assert {:ok, "report.json"} = Run.fetch_artifact(run, :report)

    assert {:error, :missing_value} = Run.put_metric(run, :time, nil)
    assert {:error, :invalid_name} = Run.put_metric(run, 17, 1)
    assert {:error, {:unknown_artifact, "missing"}} = Run.fetch_artifact(run, :missing)
  end

  test "validates constructor inputs" do
    assert {:error, {:invalid_string, :id}} = Run.new(" ", "/tmp/run")
    assert {:error, {:invalid_string, :output_dir}} = Run.new("run", nil)
    assert {:error, {:invalid_map, :params}} = Run.new("run", "/tmp/run", [])
  end
end
