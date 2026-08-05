defmodule Src.Execution.ArtifactStoreTest do
  use ExUnit.Case, async: true

  alias Src.Execution.ArtifactStore
  alias Src.Execution.Run

  test "writes artifacts and persists the run manifest" do
    output_dir = tmp_dir("write")
    assert {:ok, run} = Run.new("run-1", output_dir)

    assert {:ok, run, report_path} =
             ArtifactStore.write_json(
               run,
               :report_json,
               "nested/report.json",
               %{"status" => "completed"}
             )

    assert File.regular?(report_path)
    assert {:ok, ^report_path} = ArtifactStore.artifact_path(run, :report_json)

    assert {:ok, run, text_path} =
             ArtifactStore.write_text(run, :notes, "notes.txt", "hello\n")

    assert File.read!(text_path) == "hello\n"

    assert {:ok, manifest_path} = ArtifactStore.persist(run)
    assert File.regular?(manifest_path)

    assert {:ok, manifest} = ArtifactStore.read_manifest(run)
    assert manifest["id"] == "run-1"
    assert manifest["artifacts"]["report_json"] == "nested/report.json"
    assert manifest["artifacts"]["notes"] == "notes.txt"
  end

  test "registers existing files inside the output directory" do
    output_dir = tmp_dir("register")
    file = Path.join(output_dir, "existing.txt")
    File.write!(file, "content")
    assert {:ok, run} = Run.new("run", output_dir)

    assert {:ok, run, ^file} = ArtifactStore.register(run, :existing, file)
    assert {:ok, ^file} = ArtifactStore.artifact_path(run, "existing")
  end

  test "rejects missing and escaping artifacts" do
    output_dir = tmp_dir("reject")
    assert {:ok, run} = Run.new("run", output_dir)

    assert {:error, {:artifact_not_found, "missing.txt"}} =
             ArtifactStore.register(run, :missing, "missing.txt")

    assert {:error, {:artifact_outside_output_directory, "../outside.txt"}} =
             ArtifactStore.write_text(run, :outside, "../outside.txt", "x")

    assert {:error, {:invalid_artifact_content, :bad}} =
             ArtifactStore.write_text(run, :bad, "bad.txt", :not_text)
  end

  defp tmp_dir(label) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_artifact_store_#{label}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
