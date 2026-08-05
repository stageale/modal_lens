defmodule Src.EnumerationTest do
  use ExUnit.Case

  alias Src.Core.Model.SDL
  alias Src.Enumeration

  test "validates max_models before generating search theories" do
    dir = tmp_dir("invalid_max")
    theory = write_theory(dir, "Base")

    assert {:error, {:invalid_max_models, details}} =
             Enumeration.enumerate(theory,
               mode: :countermodels,
               max_models: 0,
               output_dir: Path.join(dir, "out")
             )

    assert details.expected == :positive_integer
    assert details.received == 0
  end

  test "validates base-theory extension and declared name" do
    dir = tmp_dir("validation")
    text = Path.join(dir, "Base.txt")
    File.write!(text, "theory Base\nimports Main\nbegin\nend\n")

    assert {:error, {:invalid_base_theory_extension, details}} =
             Enumeration.enumerate(text, mode: :countermodels)

    assert details.expected == ".thy"

    mismatched = Path.join(dir, "Expected.thy")
    File.write!(mismatched, "theory Other\nimports Main\nbegin\nend\n")

    assert {:error, {:theory_name_mismatch, mismatch}} =
             Enumeration.enumerate(mismatched, mode: :countermodels)

    assert mismatch.expected == "Expected"
    assert mismatch.declared == "Other"
  end

  test "enumerates one model without rendering visual artifacts" do
    dir = tmp_dir("enumeration")
    isabelle =
      write_executable(
        dir,
        "isabelle",
        "cat <<'OUT'\nNitpick found a counterexample for card i = 1:\nw = i⇩1\nR = (i⇩1, i⇩1) := True\nOUT\n"
      )

    base_theory = write_theory(dir, "Base_Theory")
    output_dir = Path.join(dir, "out")
    search_dir = Path.join(dir, "search")

    assert {:ok, result} =
             Enumeration.enumerate(base_theory,
               mode: :countermodels,
               model_logic: :sdl,
               max_models: 1,
               render_graph: false,
               output_dir: output_dir,
               search_theory_dir: search_dir,
               isabelle_bin: isabelle
             )

    assert result.status == :max_models_reached
    assert result.model_count == 1
    assert [entry] = result.models
    assert %SDL{} = entry.model
    assert entry.model.edges == MapSet.new([{0, 0}])
    assert entry.graph_dot_file == nil
    assert entry.graph_svg_file == nil
    assert File.exists?(entry.blocking_axiom_file)
    assert File.exists?(entry.model_json_file)
    assert result.svg_files == []
    assert result.tikz_files == []
    assert result.pdf_files == []
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
