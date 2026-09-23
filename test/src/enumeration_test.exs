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
        "cat <<'OUT'\nNitpick found a counterexample for card i = 2:\nw = i⇩1\nR = (i⇩1, i⇩1) := True\nOUT\n"
      )

    base_theory = write_theory(dir, "Base_Theory")
    output_dir = Path.join(dir, "out")
    search_dir = Path.join(dir, "search")

    assert {:ok, result} =
             Enumeration.enumerate(base_theory,
               mode: :countermodels,
               model_logic: :sdl,
               cardinalities: [2],
               max_models: 1,
               render_graph: false,
               output_dir: output_dir,
               search_theory_dir: search_dir,
               isabelle_bin: isabelle
             )

    assert result.status == :max_models_reached
    assert result.model_count == 1
    assert Enum.map(result.cardinality_results, & &1.cardinality) == [2]
    assert [entry] = result.models
    assert entry.cardinality == 2
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

  test "enumerates each cardinality independently with a per-cardinality model budget" do
    dir = tmp_dir("multi_cardinality")

    isabelle =
      write_executable(
        dir,
        "isabelle",
        ~S"""
        card=2
        for argument in "$@"; do
          if [ -f "$argument" ] && grep -q 'card i = 3' "$argument"; then
            card=3
          fi
        done
        printf 'Nitpick found a counterexample for card i = %s:\n' "$card"
        """
      )

    base_theory = write_theory(dir, "Multi_Cardinality")
    output_dir = Path.join(dir, "out")

    assert {:ok, result} =
             Enumeration.enumerate(base_theory,
               mode: :countermodels,
               model_logic: :sdl,
               cardinalities: [2, 3],
               max_models: 2,
               render_graph: false,
               output_dir: output_dir,
               isabelle_bin: isabelle
             )

    assert result.status == :max_models_reached
    assert result.model_count == 4
    assert Enum.map(result.models, & &1.cardinality) == [2, 2, 3, 3]

    assert [cardinality_2, cardinality_3] = result.cardinality_results
    assert cardinality_2.cardinality == 2
    assert cardinality_2.model_count == 2
    assert cardinality_3.cardinality == 3
    assert cardinality_3.model_count == 2

    assert Path.basename(cardinality_2.output_dir) == "cardinality_002"
    assert Path.basename(cardinality_3.output_dir) == "cardinality_003"

    for cardinality_result <- result.cardinality_results do
      assert [next_search_theory] = cardinality_result.search_theory_files
      source = File.read!(next_search_theory)
      assert length(Regex.scan(~r/Automatically generated blocking axiom/, source)) == 1
      assert source =~ "card i = #{cardinality_result.cardinality}"
    end
  end

  test "carries unused model budget into higher cardinalities" do
    dir = tmp_dir("cardinality_budget_carry")

    isabelle =
      write_executable(
        dir,
        "isabelle",
        ~S"""
        theory=""

        for argument in "$@"; do
          if [ -f "$argument" ] && grep -q 'card i = ' "$argument"; then
            theory="$argument"
          fi
        done

        if grep -q 'card i = 3' "$theory"; then
          printf 'Nitpick found a counterexample for card i = 3:\n'
          exit 0
        fi

        blocking_count=$(
          grep -c 'Automatically generated blocking axiom' "$theory" ||
            true
        )

        if [ "$blocking_count" -ge 1 ]; then
          printf 'Nitpick found no counterexample\n'
        else
          printf 'Nitpick found a counterexample for card i = 2:\n'
        fi
        """
      )

    base_theory = write_theory(dir, "Cardinality_Budget_Carry")
    output_dir = Path.join(dir, "out")

    assert {:ok, result} =
             Enumeration.enumerate(base_theory,
               mode: :countermodels,
               model_logic: :sdl,
               cardinalities: [2, 3],
               max_models: 2,
               render_graph: false,
               output_dir: output_dir,
               isabelle_bin: isabelle
             )

    # Gesamtziel: 2 Kardinalitäten × Grundquote 2 = 4 Modelle.
    assert result.model_count == 4
    assert result.status == :max_models_reached
    assert Enum.map(result.models, & &1.cardinality) == [2, 3, 3, 3]

    assert [cardinality_2, cardinality_3] =
             result.cardinality_results

    assert cardinality_2.status == :exhausted
    assert cardinality_2.model_count == 1

    # Das bei Kardinalität 2 ungenutzte Modell wird auf 3 übertragen.
    assert cardinality_3.status == :max_models_reached
    assert cardinality_3.model_count == 3
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
        "modal_lens_enumeration_#{label}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
