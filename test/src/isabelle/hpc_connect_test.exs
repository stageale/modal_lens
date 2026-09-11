defmodule Src.Isabelle.HPCConnectTest do
  use ExUnit.Case

  alias HpcConnect.Command
  alias Src.Isabelle.HPCConnect

  defmodule FakeHpcConnect do
    alias HpcConnect.Command

    def new_session(cluster, opts) do
      send(Process.get(:hpc_test_pid), {:new_session, cluster, opts})
      :fake_session
    end

    def connect!(session, remote_command, opts) do
      send(Process.get(:hpc_test_pid), {:connect, session, remote_command, opts})

      command = %Command{
        binary: "ssh",
        args: ["aion-cluster", "bash -lc remote"],
        summary: "fake SSH command",
        remote_command: remote_command
      }

      run_fun = Keyword.fetch!(opts, :run_fun)
      run_opts = Keyword.drop(opts, [:run_fun, :connect_preflight_fun])
      run_fun.(command, run_opts)
    end

    def run_command!(command, opts) do
      send(Process.get(:hpc_test_pid), {:run_command, command, opts})
      "remote build log"
    end
  end

  defmodule FailingHpcConnect do
    def new_session(_cluster, _opts), do: raise("bootstrap unavailable")
  end

  defmodule FakeTransfer do
    def upload!(session, local_path, remote_path, opts) do
      send(
        Process.get(:hpc_test_pid),
        {:upload, session, local_path, remote_path, opts}
      )

      :ok
    end
  end

  defmodule FailingTransfer do
    def upload!(_session, _local_path, _remote_path, _opts) do
      raise "upload unavailable"
    end
  end

  setup do
    Process.put(:hpc_test_pid, self())
    on_exit(fn -> Process.delete(:hpc_test_pid) end)
    :ok
  end

  test "stages the complete workdir and submits Isabelle through SLURM" do
    workdir = tmp_dir()
    root_text = "session Remote = HOL +\n"
    theory_text = "theory Remote\nimports Main\nbegin\nend\n"

    File.write!(Path.join(workdir, "ROOT"), root_text)
    File.write!(Path.join(workdir, "Remote.thy"), theory_text)

    File.write!(
      Path.join(workdir, "Imported.thy"),
      "theory Imported\nimports Main\nbegin\nend\n"
    )

    assert {:ok, "remote build log"} =
             HPCConnect.run(workdir, %{theory_name: "Remote"},
               hpc_module: FakeHpcConnect,
               transfer_module: FakeTransfer,
               remote_dir: "runs/remote",
               remote_preamble: "module load isabelle",
               job: [cpus_per_task: 6, time_limit: "00:12:00"],
               connect_opts: [timeout: 5],
               transfer_opts: [timeout: 10_000]
             )

    assert_receive {:new_session, cluster, session_opts}
    assert cluster.name == :aion
    assert cluster.default_work_dir == "modal_lens_runtime"
    assert cluster.vault_dir == "modal_lens_vault"
    assert session_opts[:ssh_alias] == "aion-cluster"
    assert session_opts[:username] == nil
    assert session_opts[:identity_file] == nil
    assert session_opts[:proxy_jump] == nil

    assert_receive {:connect, :fake_session, prepare_command, prepare_connect_opts}
    assert prepare_connect_opts[:timeout] == 5
    assert is_function(prepare_connect_opts[:run_fun], 2)
    assert prepare_command =~ "mkdir -p -- 'runs'"
    assert prepare_command =~ "test ! -e 'runs/remote'"

    assert_receive {:run_command, %Command{} = prepare_ssh_command, prepare_run_opts}
    assert prepare_ssh_command.remote_command == prepare_command
    assert_batch_mode(prepare_ssh_command)
    assert prepare_run_opts[:timeout] == 5
    assert prepare_run_opts[:retries] == 3

    assert_receive {:upload, :fake_session, ^workdir, "runs/remote", transfer_opts}
    assert transfer_opts[:recursive]
    assert transfer_opts[:retries] == 0
    assert transfer_opts[:timeout] == 10_000

    assert_receive {:connect, :fake_session, job_command, job_connect_opts}
    assert job_connect_opts[:timeout] == 5
    assert is_function(job_connect_opts[:run_fun], 2)
    assert job_command =~ "cd -- 'runs/remote'"
    assert job_command =~ "sbatch --parsable --wait --nodes=1 --ntasks=1"
    assert job_command =~ "--cpus-per-task='6'"
    assert job_command =~ "--time='00:12:00'"
    refute job_command =~ "'isabelle' build"

    batch_script = decode_batch_script(job_command)
    assert batch_script =~ "module load isabelle"
    assert batch_script =~ "exec '/home/users/astage/opt/Isabelle2025-2/bin/isabelle' process_theories"
    assert batch_script =~ "-l 'HOL'"
    assert batch_script =~ "-o 'threads=6'"
    assert batch_script =~ "-f 'Remote.thy'"

    assert_receive {:run_command, %Command{} = job_ssh_command, job_run_opts}
    assert job_ssh_command.remote_command == job_command
    assert_batch_mode(job_ssh_command)
    assert job_run_opts[:timeout] == 5
    assert job_run_opts[:retries] == 0
  end

  test "reports workdir staging failures" do
    workdir = tmp_dir()
    File.write!(Path.join(workdir, "ROOT"), "session Remote = HOL +\n")

    File.write!(
      Path.join(workdir, "Remote.thy"),
      "theory Remote\nimports Main\nbegin\nend\n"
    )

    assert {:error, {:hpc_execution_failed, "upload unavailable"}} =
             HPCConnect.run(workdir, %{theory_name: "Remote"},
               hpc_module: FakeHpcConnect,
               transfer_module: FailingTransfer,
               remote_dir: "runs/remote"
             )
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

    assert {:error, {:hpc_connect_not_available, ^missing_module}} =
             HPCConnect.run(
               workdir,
               %{theory_name: "Remote"},
               hpc_module: missing_module
             )

    assert {:error, {:hpc_bootstrap_failed, "bootstrap unavailable"}} =
             HPCConnect.run(workdir, %{theory_name: "Remote"}, hpc_module: FailingHpcConnect)
  end

  test "reports missing generated Isabelle files" do
    workdir = tmp_dir()

    assert {:error, {:cannot_read_isabelle_file, path, :enoent}} =
             HPCConnect.run(workdir, %{theory_name: "Remote"}, hpc_module: FakeHpcConnect)

    assert path == Path.join(workdir, "ROOT")
  end

  test "rejects unsupported schedulers and invalid SLURM resources" do
    workdir = tmp_dir()
    File.write!(Path.join(workdir, "ROOT"), "session Remote = HOL +\n")

    File.write!(
      Path.join(workdir, "Remote.thy"),
      "theory Remote\nimports Main\nbegin\nend\n"
    )

    assert {:error, {:unsupported_hpc_scheduler, :pbs}} =
             HPCConnect.run(workdir, %{theory_name: "Remote"},
               hpc_module: FakeHpcConnect,
               scheduler: :pbs
             )

    assert {:error, {:invalid_hpc_option, :cpus_per_task, 0}} =
             HPCConnect.run(workdir, %{theory_name: "Remote"},
               hpc_module: FakeHpcConnect,
               job: [cpus_per_task: 0]
             )

    assert {:error, {:invalid_hpc_option, :time_limit, ""}} =
             HPCConnect.run(workdir, %{theory_name: "Remote"},
               hpc_module: FakeHpcConnect,
               job: [time_limit: ""]
             )

    assert {:error, {:invalid_hpc_option, :ssh_alias, ""}} =
             HPCConnect.run(workdir, %{theory_name: "Remote"},
               hpc_module: FakeHpcConnect,
               ssh_alias: ""
             )
  end

  defp decode_batch_script(remote_command) do
    [encoded] =
      Regex.run(
        ~r/printf '%s' '([^']+)' \| base64 --decode > job\.sh/,
        remote_command,
        capture: :all_but_first
      )

    Base.decode64!(encoded)
  end

  defp assert_batch_mode(command) do
    assert command.args == [
             "-T",
             "-n",
             "-o",
             "BatchMode=yes",
             "aion-cluster",
             "bash -lc remote"
           ]
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_hpc_test_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(dir)

    on_exit(fn ->
      File.rm_rf!(dir)
    end)

    dir
  end
end
