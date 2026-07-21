defmodule Src.Interface.Isabelle.ClientTest do
  use ExUnit.Case, async: true

  alias Src.Interface.Isabelle.Client
  alias Src.Interface.Isabelle.HOLEmbedding

  test "rejects missing and non-theory files" do
    missing = Path.join(tmp_dir(), "missing.thy")
    assert Client.nitpick_theory(missing) == {:error, {:theory_not_found, Path.expand(missing)}}

    text_file = Path.join(tmp_dir(), "not_theory.txt")
    File.write!(text_file, "theory Example")

    assert Client.nitpick_theory(text_file) ==
             {:error, {:not_an_isabelle_theory, Path.expand(text_file)}}
  end

  test "requires an Isabelle theory declaration" do
    path = Path.join(tmp_dir(), "MissingDeclaration.thy")
    File.write!(path, "imports Main\nbegin\nend\n")

    assert Client.nitpick_theory(path) ==
             {:error, {:missing_theory_declaration, Path.expand(path)}}
  end

  test "requires the theory to be inside the selected workdir" do
    dir = tmp_dir()
    other_dir = tmp_dir()
    path = Path.join(dir, "Example.thy")
    File.write!(path, "theory Example\nimports Main\nbegin\nend\n")

    assert {:error, {:theory_outside_workdir, details}} =
             Client.nitpick_theory(path, workdir: other_dir)

    assert details.theory_path == Path.expand(path)
    assert details.workdir == Path.expand(other_dir)
  end

  test "generated theories reject unknown backends after writing their inputs" do
    workdir = tmp_dir()
    spec = HOLEmbedding.new(theory_name: "Generated_Test")

    assert {:error, {:unknown_backend, :unknown}} =
             Client.nitpick_countermodel(spec,
               backend: :unknown,
               workdir: workdir
             )

    assert File.exists?(Path.join(workdir, "ROOT"))
    assert File.exists?(Path.join(workdir, "Generated_Test.thy"))
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_client_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
