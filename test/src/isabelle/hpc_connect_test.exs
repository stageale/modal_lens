defmodule Src.Isabelle.HPCConnectTest do
  use ExUnit.Case

  alias Src.Isabelle.HPCConnect

  defmodule FakeHpcConnect do
    def new_session(cluster, opts) do
      send(Process.get(:hpc_test_pid), {:new_session, cluster, opts})
      :fake_session
    end

    def connect!(session, command, opts) do
      send(Process.get(:hpc_test_pid), {:connect, session, command, opts})
      "remote build log"
    end
  end

  defmodule FailingHpcConnect do
    def new_session(_cluster, _opts), do: raise("bootstrap unavailable")
  end

  setup do
    Process.put(:hpc_test_pid, self())
    on_exit(fn -> Process.delete(:hpc_test_pid) end)
    :ok
  end

  test "uploads generated files and runs Isabelle through an injected backend" do
    workdir = tmp_dir()
    File.write!(Path.join(workdir, "ROOT"), "session Remote = HOL +\n")
    File.write!(Path.join(workdir, "Remote.thy"), "theory Remote\nimports Main\nbegin\nend\n")

    assert {:ok, "remote build log"} =
             HPCConnect.run(workdir, %{theory_name: "Remote"},
               hpc_module: FakeHpcConnect,
               remote_dir: "runs/remote",
               username: "alex",
               connect_opts: [timeout: 5]
             )

    assert_receive {:new_session, cluster, session_opts}
    assert cluster.name == :aion
    assert session_opts[:username] == "alex"

    assert_receive {:connect, :fake_session, command, [timeout: 5]}
    assert command =~ "mkdir -p 'runs/remote'"
    assert command =~ "base64 --decode > 'runs/remote/ROOT'"
    assert command =~ "base64 --decode > 'runs/remote/Remote.thy'"
    assert command =~ "'isabelle' build"
    assert command =~ "'Remote'"
  end

  test "reports unavailable modules and bootstrap failures" do
    workdir = tmp_dir()

    File.write!(
      Path.join(workdir, "ROOT"),
      "session Remote = HOL +\n"
    )

    File.write!(
      Path.join(workdir, "Remote.thy"),
      "theory Remote\nimports Main\nbegin\nend\n"
    )

    missing_module = Module.concat(__MODULE__, "MissingDependency")

    assert {:error,
            {:hpc_connect_not_available,
             ^missing_module}} =
             HPCConnect.run(
               workdir,
               %{theory_name: "Remote"},
               hpc_module: missing_module
             )

    assert {:error, {:hpc_bootstrap_failed, "bootstrap unavailable"}} =
             HPCConnect.run(workdir, %{theory_name: "Remote"},
               hpc_module: FailingHpcConnect
             )
  end

  test "reports missing generated Isabelle files" do
    workdir = tmp_dir()

    assert {:error, {:cannot_read_isabelle_file, path, :enoent}} =
             HPCConnect.run(workdir, %{theory_name: "Remote"},
               hpc_module: FakeHpcConnect
             )

    assert path == Path.join(workdir, "ROOT")
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_hpc_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
