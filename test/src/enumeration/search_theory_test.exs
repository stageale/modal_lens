defmodule Src.Enumeration.SearchTheoryTest do
  use ExUnit.Case, async: true

  alias Src.Enumeration.SearchTheory

  test "writes a numbered search theory with relative import and blocking axioms" do
    root = tmp_dir()
    base_dir = Path.join(root, "input")
    search_dir = Path.join(root, "generated")
    File.mkdir_p!(base_dir)

    base = Path.join(base_dir, "Example.thy")
    File.write!(base, "theory Example\nimports Main\nbegin\nend\n")

    blocks = [
      ~S(axiomatization where ax_first: "P"),
      ~S(axiomatization where ax_second: "Q")
    ]

    assert {:ok, result} =
             SearchTheory.write(base, blocks,
               mode: :countermodels,
               search_theory_dir: search_dir
             )

    assert result.theory_name == "Example_Search_002"
    assert result.cardinality == 2
    assert result.block_count == 2
    assert result.blocking_axioms == blocks
    assert File.regular?(result.theory_path)

    source = File.read!(result.theory_path)
    assert source =~ "theory Example_Search_002"
    assert source =~ ~s(imports "../input/Example")
    assert source =~ "Automatically generated blocking axiom 1"
    assert source =~ "ax_first"
    assert source =~ "Automatically generated blocking axiom 2"
    assert source =~ "ax_second"
    assert source =~ "(* MODAL_LENS_BLOCKS *)"
    assert source =~ "card i = 2"
  end

  test "writes the requested Nitpick cardinality" do
    root = tmp_dir()
    base = Path.join(root, "Example.thy")
    target = Path.join(root, "generated")
    File.write!(base, "theory Example\nimports Main\nbegin\nend\n")

    assert {:ok, result} =
             SearchTheory.write(base, [],
               mode: :countermodels,
               cardinality: 4,
               search_theory_dir: target
             )

    assert result.cardinality == 4
    source = File.read!(result.theory_path)
    assert source =~ "card i = 4"
    refute source =~ "card i = 2"
  end

  test "rejects invalid cardinalities" do
    root = tmp_dir()
    base = Path.join(root, "Example.thy")
    File.write!(base, "theory Example\nimports Main\nbegin\nend\n")

    assert {:error, {:invalid_cardinality, details}} =
             SearchTheory.write(base, [],
               mode: :countermodels,
               cardinality: 0
             )

    assert details.expected == :positive_integer
    assert details.received == 0
  end

  test "selects templates for all enumeration modes" do
    root = tmp_dir()
    base = Path.join(root, "Example.thy")
    File.write!(base, "theory Example\nimports Main\nbegin\nend\n")

    for mode <- [:countermodels, :satisfying_models, :consistency_check] do
      target = Path.join(root, Atom.to_string(mode))
      assert {:ok, result} = SearchTheory.write(base, [], mode: mode, search_theory_dir: target)
      assert result.mode == mode
      assert File.read!(result.theory_path) =~ "Example_Search_000"
    end
  end

  test "rejects empty blocking axioms" do
    root = tmp_dir()
    base = Path.join(root, "Example.thy")
    File.write!(base, "theory Example\nimports Main\nbegin\nend\n")

    assert {:error, {:invalid_blocking, [""]}} =
             SearchTheory.write(base, [""], mode: :countermodels)
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_search_theory_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
