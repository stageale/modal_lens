defmodule Src.Explanation.Verbal.JobTest do
  use ExUnit.Case, async: true

  alias Src.Explanation.Verbal.Job

  test "builds and writes a verbalization request" do
    output_dir = tmp_dir()
    request_path = Job.build_request_path(output_dir)

    assert {:ok, job} =
             Job.new(
               "transformers",
               "test/model",
               "/tmp/report.json",
               output_dir
             )

    assert job.seed == 42
    assert job.max_new_tokens == 768
    assert {:ok, ^request_path} = Job.write(job, request_path)

    request =
      request_path
      |> File.read!()
      |> Jason.decode!()

    assert request["backend"] == "transformers"
    assert request["model_id"] == "test/model"
    assert request["seed"] == 42
  end

  defp tmp_dir do
    Path.join(
      System.tmp_dir!(),
      "verbal_job_#{System.unique_integer([:positive])}"
    )
  end
end
