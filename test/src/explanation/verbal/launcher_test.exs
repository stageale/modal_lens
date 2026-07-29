defmodule Src.Explanation.Verbal.LauncherTest do
  use ExUnit.Case, async: true

  alias Src.Explanation.Verbal.Launcher

  test "writes a request and returns the Python response" do
    root = tmp_dir()
    fake_uv = Path.join(root, "uv")

    File.mkdir_p!(root)

    File.write!(
      fake_uv,
      """
      #!/bin/sh
      echo '{"status":"completed","artifacts":{}}'
      """
    )

    File.chmod!(fake_uv, 0o755)

    assert {:ok, launch} =
             Launcher.launch(
               "/tmp/report.json",
               root,
               "transformers",
               "Test/Model",
               uv_executable: fake_uv,
               project_root: root
             )

    assert launch.response["status"] == "completed"
    assert File.exists?(launch.request_path)
    assert launch.job.output_directory == Path.join(root, "test-model")
  end

  defp tmp_dir do
    Path.join(
      System.tmp_dir!(),
      "verbal_launcher_#{System.unique_integer([:positive])}"
    )
  end
end
