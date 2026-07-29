defmodule Src.Interface.Common.ArtifactStoreTest do
  use ExUnit.Case, async: true

  alias Src.Interface.Common.ArtifactStore
  alias Src.Interface.Common.Run

  test "writes artifacts and persists the run manifest" do
    output_dir =
      Path.join(
        System.tmp_dir!(),
        "artifact_store_#{System.unique_integer([:positive])}"
      )

    assert {:ok, run} = Run.new("run-1", output_dir)

    assert {:ok, run, report_path} =
             ArtifactStore.write_json(
               run,
               :report_json,
               "report.json",
               %{"status" => "completed"}
             )

    assert File.regular?(report_path)

    assert {:ok, ^report_path} =
             ArtifactStore.artifact_path(run, :report_json)

    assert {:ok, manifest_path} =
             ArtifactStore.persist(run)

    assert File.regular?(manifest_path)

    assert {:ok, manifest} =
             ArtifactStore.read_manifest(run)

    assert manifest["id"] == "run-1"
    assert manifest["artifacts"]["report_json"] == "report.json"
  end
end
