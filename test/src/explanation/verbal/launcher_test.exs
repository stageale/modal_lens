defmodule Src.Explanation.Verbal.LauncherTest do
  use ExUnit.Case, async: true

  alias Src.Explanation.Verbal.Launcher

  test "writes a request and returns the last valid Python response" do
    root = tmp_dir()

    fake_uv =
      executable(root, "uv", """
      echo 'diagnostic output'
      echo '{"status":"completed","artifacts":{}}'
      """)

    assert {:ok, launch} =
             Launcher.launch(
               "/tmp/report.json",
               root,
               "transformers",
               "Test/Model",
               uv_executable: fake_uv,
               project_root: root,
               verbalization_mode: :interpretive,
               reasoning: true
             )

    assert launch.response["status"] == "completed"
    assert File.exists?(launch.request_path)
    assert launch.job.output_directory == Path.join(root, "test-model")

    request = launch.request_path |> File.read!() |> Jason.decode!()
    assert request["schema"] == "modal-lens/verbalization-request"
    assert request["verbalization_mode"] == "interpretive"
    assert request["reasoning"] == true
  end

  test "returns structured errors for failing and malformed launchers" do
    root = tmp_dir()
    failing = executable(root, "failing", "echo boom\nexit 4\n")

    assert {:error, error} =
             Launcher.run_request("request.json",
               uv_executable: failing,
               project_root: root
             )

    assert error.reason == :python_launcher_failed
    assert error.exit_status == 4
    assert error.output =~ "boom"

    malformed = executable(root, "malformed", "echo not-json\n")

    assert {:error, malformed_error} =
             Launcher.run_request("request.json",
               uv_executable: malformed,
               project_root: root
             )

    assert malformed_error.reason == :invalid_python_response
  end

  defp executable(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "verbal_launcher_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end

  test "runs multiple requests in one Python process" do
    root = tmp_dir()
    arguments_file = Path.join(root, "arguments.txt")

    fake_uv =
      executable(root, "uv", """
      printf '%s\\n' "$@" > "#{arguments_file}"
      echo '{"status":"completed","jobs":[]}'
      """)

    request_a = Path.join(root, "a.json")
    request_b = Path.join(root, "b.json")

    assert {:ok, response} =
             Launcher.run_requests(
               [request_a, request_b],
               uv_executable: fake_uv,
               project_root: root
             )

    assert response["status"] == "completed"

    arguments = File.read!(arguments_file)

    assert arguments =~ Path.expand(request_a)
    assert arguments =~ Path.expand(request_b)
  end

  test "rejects an empty request batch" do
    assert {:error, %{reason: :no_verbalization_requests}} =
             Launcher.run_requests([])
  end
end
