defmodule Src.ModelEnumerationTest do
  use ExUnit.Case

  alias Src.Core.Model.SDL
  alias Src.ModelEnumeration

  setup do
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      if previous_path do
        System.put_env("PATH", previous_path)
      else
        System.delete_env("PATH")
      end
    end)

    :ok
  end

  test "validates iteration numbers before invoking Isabelle" do
    assert {:error, {:invalid_iteration, details}} =
             ModelEnumeration.run_iteration("missing.thy",
               iteration: 0,
               mode: :countermodels,
               output_dir: tmp_dir("invalid_iteration")
             )

    assert details.expected == :positive_integer
    assert details.received == 0
  end

  test "validates max_models before generating search theories" do
    assert {:error, {:invalid_max_models, details}} =
             ModelEnumeration.enumerate("base.thy",
               mode: :countermodels,
               max_models: 0,
               output_dir: tmp_dir("invalid_max")
             )

    assert details.expected == :positive_integer
    assert details.received == 0
  end

  test "returns a terminal no-countermodel result" do
    dir = tmp_dir("no_result")
    theory = write_theory(dir, "No_Result")

    isabelle =
      write_executable(
        dir,
        "fake_isabelle",
        "cat <<'EOF'\nNitpick found no counterexample\nEOF\n"
      )

    assert {:ok, result} =
             ModelEnumeration.run_iteration(theory,
               mode: :countermodels,
               isabelle_bin: isabelle,
               output_dir: Path.join(dir, "out")
             )

    assert result.status == :no_countermodel
    assert result.model == nil
    assert result.graph_dot_file == nil
    assert File.read!(result.nitpick_output_file) =~ "Nitpick found no counterexample"
  end

  test "enumerates one model with fake Isabelle and GraphViz executables" do
    dir = tmp_dir("enumeration")
    bin_dir = Path.join(dir, "bin")
    File.mkdir_p!(bin_dir)

    isabelle =
      write_executable(
        bin_dir,
        "isabelle",
        "cat <<'EOF'\nNitpick found a counterexample for card i = 1:\nw = i⇩1\nR = (i⇩1, i⇩1) := True\nEOF\n"
      )

    _dot =
      write_executable(
        bin_dir,
        "dot",
        "out=''\nwhile [ \"$#\" -gt 0 ]; do\n  if [ \"$1\" = '-o' ]; then\n    shift\n    out=\"$1\"\n  fi\n  shift\ndone\nprintf '<svg/>\\n' > \"$out\"\n"
      )

    System.put_env("PATH", bin_dir <> ":" <> (System.get_env("PATH") || ""))

    base_theory = write_theory(dir, "Base_Theory")
    output_dir = Path.join(dir, "out")
    search_dir = Path.join(dir, "search")

    assert {:ok, result} =
             ModelEnumeration.enumerate(base_theory,
               mode: :countermodels,
               model_logic: :sdl,
               max_models: 1,
               output_dir: output_dir,
               search_theory_dir: search_dir,
               isabelle_bin: isabelle
             )

    assert result.status == :max_models_reached
    assert result.model_count == 1
    assert [entry] = result.models
    assert %SDL{} = entry.model
    assert entry.model.edges == MapSet.new([{0, 0}])
    assert File.exists?(entry.graph_dot_file)
    assert File.read!(entry.graph_svg_file) == "<svg/>\n"
    assert File.exists?(entry.blocking_axiom_file)
    assert entry.blocking_axiom =~ "axiomatization where"
  end

  defp write_theory(dir, name) do
    path = Path.join(dir, "#{name}.thy")
    File.write!(path, "theory #{name}\nimports Main\nbegin\nend\n")
    path
  end

  defp write_executable(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\nset -e\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  defp tmp_dir(label) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_enumeration_#{label}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
