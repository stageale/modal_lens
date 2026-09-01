defmodule Src.TPTP.Backend.Leo3Test do
  use ExUnit.Case, async: true

  alias Src.TPTP.Backend.Leo3

  test "runs Leo-III compatible executable and extracts theorem proof" do
    root = temp_dir!()
    problem = Path.join(root, "problem.p")
    executable = Path.join(root, "fake_leo3")

    File.write!(problem, "thf(goal,conjecture,$true).\n")

    File.write!(executable, """
    #!/bin/sh
    echo "% SZS status Theorem for $1"
    echo "% SZS output start Refutation for $1"
    echo "thf(step1,plain,\\$false,inference(test,[],[]))."
    echo "% SZS output end Refutation for $1"
    exit 0
    """)

    File.chmod!(executable, 0o755)

    assert {:ok, result} =
             Leo3.run(problem,
               executable: executable,
               timeout: 7,
               proof: true
             )

    assert result.backend == :leo_iii
    assert result.problem == problem
    assert result.status == :theorem
    assert result.exit_status == 0
    assert result.proof == "thf(step1,plain,$false,inference(test,[],[]))."
    assert result.output =~ "% SZS status Theorem"
  end

  test "preserves operational SZS results even with non-zero exit status" do
    root = temp_dir!()
    problem = Path.join(root, "problem.p")
    executable = Path.join(root, "fake_leo3")

    File.write!(problem, "thf(goal,conjecture,$true).\n")

    File.write!(executable, """
    #!/bin/sh
    echo "% SZS status TypeError for $1"
    exit 2
    """)

    File.chmod!(executable, 0o755)

    assert {:ok, result} = Leo3.run(problem, executable: executable)
    assert result.status == :type_error
    assert result.exit_status == 2
    assert result.proof == nil
  end

  test "reports executables that cannot be started" do
    missing = Path.join(temp_dir!(), "definitely_missing_leo3")

    assert {:error, {:executable_not_found, ^missing}} =
             Leo3.run("problem.p", executable: missing)
  end

  defp temp_dir! do
    path =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_leo_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
