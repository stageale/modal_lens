defmodule Src.Explanation.Verbal.JobTest do
  use ExUnit.Case, async: true

  alias Src.Explanation.Verbal.Job

  test "builds and writes a versioned verbalization request" do
    output_dir = tmp_dir()
    request_path = Job.build_request_path(output_dir)

    assert {:ok, job} =
             Job.new(
               "transformers",
               "test/model",
               "/tmp/report.json",
               output_dir,
               seed: 7,
               max_new_tokens: 128,
               backend_options: %{device: "cpu"}
             )

    assert {:ok, ^request_path} = Job.write(job, request_path)

    request = request_path |> File.read!() |> Jason.decode!()

    assert request["schema"] == "axiom-refiner/verbalization-request"
    assert request["schema_version"] == "1.0"
    assert request["backend"] == "transformers"
    assert request["model_id"] == "test/model"
    assert request["report_path"] == "/tmp/report.json"
    assert request["output_directory"] == output_dir
    assert request["seed"] == 7
    assert request["max_new_tokens"] == 128
    assert request["backend_options"] == %{"device" => "cpu"}
  end

  test "uses reproducible defaults" do
    assert {:ok, job} = Job.new("ollama", "model", "report.json", "out")
    assert job.seed == 42
    assert job.max_new_tokens == 768
    assert job.backend_options == %{}
  end

  test "rejects invalid request values" do
    assert {:error, {:invalid_backend, ["transformers", "ollama"]}} =
             Job.new("other", "model", "report.json", "out")

    assert {:error, {:invalid_string, :model_id}} =
             Job.new("ollama", " ", "report.json", "out")

    assert {:error, {:invalid_non_negative_integer, :seed}} =
             Job.new("ollama", "model", "report.json", "out", seed: -1)

    assert {:error, {:invalid_positive_integer, :max_new_tokens}} =
             Job.new("ollama", "model", "report.json", "out", max_new_tokens: 0)

    assert {:error, :invalid_backend_options} =
             Job.new("ollama", "model", "report.json", "out", backend_options: [])
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "verbal_job_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
