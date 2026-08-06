defmodule Src.Isabelle.LocalConnectTest do
  use ExUnit.Case

  alias Src.Isabelle.LocalConnect

  setup do
    previous = System.get_env("MODAL_LENS_ISABELLE_BIN")

    on_exit(fn ->
      if previous do
        System.put_env("MODAL_LENS_ISABELLE_BIN", previous)
      else
        System.delete_env("MODAL_LENS_ISABELLE_BIN")
      end
    end)

    :ok
  end

  test "resolves the executable from options, environment, or default" do
    System.put_env("MODAL_LENS_ISABELLE_BIN", "/env/isabelle")
    assert LocalConnect.configured_isabelle_bin(isabelle_bin: "/opt/isabelle") == "/opt/isabelle"
    assert LocalConnect.configured_isabelle_bin() == "/env/isabelle"

    System.delete_env("MODAL_LENS_ISABELLE_BIN")
    assert LocalConnect.configured_isabelle_bin() == "isabelle"
  end

  test "runs version and returns command metadata for failures" do
    success = executable("success", "printf '%s\\n' \"$@\"\n")
    assert {:ok, "version\n"} = LocalConnect.version(isabelle_bin: success)

    failure = executable("failure", "echo failed\nexit 7\n")
    assert {:error, error} = LocalConnect.version(isabelle_bin: failure)
    assert error.status == 7
    assert error.output == "failed\n"
    assert error.command == [failure, "version"]
  end

  test "reports executables that cannot be started" do
    missing = Path.join(tmp_dir(), "does-not-exist")
    assert {:error, error} = LocalConnect.version(isabelle_bin: missing)
    assert error.status == :failed_to_start
    assert error.output =~ "Could not start Isabelle executable"
    assert error.output =~ missing
  end

  test "passes build and process-theory arguments" do
    script = executable("args", "printf '%s\\n' \"$@\"\n")
    workdir = tmp_dir()
    theory = Path.join(workdir, "Example.thy")
    File.write!(theory, "theory Example\nimports Main\nbegin\nend\n")

    assert {:ok, build_output} =
             LocalConnect.build(workdir, %{theory_name: "Example"},
               isabelle_bin: script,
               threads: 3
             )

    assert build_output =~ "build\n-j\n1\n-d\n#{workdir}\n"
    assert build_output =~ "threads=3"
    assert build_output =~ "Example"

    assert {:ok, process_output} =
             LocalConnect.process_theory(theory,
               isabelle_bin: script,
               logic: "HOL",
               threads: 2
             )

    assert process_output =~ "process_theories"
    assert process_output =~ "threads=2"
    assert process_output =~ Path.expand(theory)
  end

  defp executable(name, body) do
    path = Path.join(tmp_dir(), name)
    File.write!(path, "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_local_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
