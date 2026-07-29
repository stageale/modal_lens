"""
defmodule Src.Interface.Isabelle.HPCConnectTest do
  use ExUnit.Case

  alias Src.Interface.Isabelle.HPCConnect

  defmodule FakeHpcConnect do
    def bootstrap(opts) do
      notify({:bootstrap, opts})
      %{session: :fake_session}
    end

    def connect!(session, command, opts) do
      notify({:connect, session, command, opts})

      if String.contains?(command, " build -D ") do
        "remote build log"
      else
        "ok"
      end
    end

    defp notify(message) do
      send(Process.get(:axiom_refiner_hpc_test_pid), message)
    end
  end

  defmodule FailingBootstrap do
    def bootstrap(_opts), do: raise("bootstrap unavailable")
  end

  setup do
    Process.put(:axiom_refiner_hpc_test_pid, self())
    on_exit(fn -> Process.delete(:axiom_refiner_hpc_test_pid) end)
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

    assert_receive {:bootstrap, bootstrap_opts}
    assert bootstrap_opts[:username] == "alex"
    assert bootstrap_opts[:install_scripts] == false
    assert bootstrap_opts[:install_def_files] == false

    assert_receive {:connect, :fake_session, mkdir_command, [timeout: 5]}
    assert mkdir_command =~ "mkdir -p 'runs/remote'"

    assert_receive {:connect, :fake_session, root_upload, [timeout: 5]}
    assert root_upload =~ "cat > 'runs/remote/ROOT'"

    assert_receive {:connect, :fake_session, theory_upload, [timeout: 5]}
    assert theory_upload =~ "cat > 'runs/remote/Remote.thy'"

    assert_receive {:connect, :fake_session, build_command, [timeout: 5]}
    assert build_command =~ "isabelle' build -D ."
    assert build_command =~ "'Remote'"
  end

  test "reports unavailable modules before reading files" do
    missing_module = Module.concat(__MODULE__, "MissingDependency")

    assert {:error, {:hpc_connect_not_available, message}} =
             HPCConnect.run(tmp_dir(), %{theory_name: "Remote"},
               hpc_module: missing_module
             )

    assert message =~ inspect(missing_module)
  end

  test "wraps bootstrap failures" do
    assert {:error, {:hpc_bootstrap_failed, "bootstrap unavailable"}} =
             HPCConnect.run(tmp_dir(), %{theory_name: "Remote"},
               hpc_module: FailingBootstrap
             )
  end

  test "reports missing generated Isabelle files" do
    workdir = tmp_dir()

    assert {:error, {:missing_generated_isabelle_file, path, :enoent}} =
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
"""
