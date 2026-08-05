defmodule Src.Isabelle.HOLEmbeddingTest do
  use ExUnit.Case, async: true

  alias Src.Isabelle.HOLEmbedding

  test "creates an embedding with defaults and overrides" do
    default = HOLEmbedding.new()
    assert default.theory_name == "Axiom_Refiner_Run"
    assert default.imports == ["Main"]
    assert default.goal == "False"

    custom = HOLEmbedding.new(theory_name: "Custom", atoms: ["p"], goal: "p w")
    assert custom.theory_name == "Custom"
    assert custom.atoms == ["p"]
    assert custom.goal == "p w"
  end

  test "renders a complete Isabelle theory" do
    spec =
      HOLEmbedding.new(
        theory_name: "Generated",
        imports: ["Main", "HOL-Library.Multiset"],
        atoms: ["p", "q"],
        axioms: ["serial r", "reflexive r"],
        goal: "p w",
        nitpick_options: ["user_axioms", "card i = 2"]
      )

    source = HOLEmbedding.render_theory(spec)

    assert source =~ "theory Generated"
    assert source =~ "imports Main HOL-Library.Multiset"
    assert source =~ ~S(consts r :: "i \<Rightarrow> i \<Rightarrow> bool")
    assert source =~ ~S(consts p :: "i \<Rightarrow> bool")
    assert source =~ "ax_generated_1"
    assert source =~ "serial r"
    assert source =~ ~s("p w")
    assert source =~ "nitpick [user_axioms, card i = 2]"
  end

  test "writes theory and ROOT files" do
    dir = tmp_dir()
    spec = HOLEmbedding.new(theory_name: "Written")

    theory_path = HOLEmbedding.write_theory!(spec, dir)
    root_path = HOLEmbedding.write_root!(spec, dir)

    assert theory_path == Path.join(dir, "Written.thy")
    assert root_path == Path.join(dir, "ROOT")
    assert File.read!(theory_path) =~ "theory Written"
    assert File.read!(root_path) =~ "session Written = HOL +"
  end

  test "renders supported frame axioms" do
    assert HOLEmbedding.frame_axiom(:serial) == "serial r"
    assert HOLEmbedding.frame_axiom("R", :reflexive) == "reflexive R"
    assert HOLEmbedding.frame_axiom("R", :symmetric) == "symmetric R"
    assert HOLEmbedding.frame_axiom("R", :transitive) == "transitive R"
    assert HOLEmbedding.frame_axiom("R", :euclidean) == "euclidean R"
    assert HOLEmbedding.frame_axiom("R", :functional) == "functional R"
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_embedding_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
