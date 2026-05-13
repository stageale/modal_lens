defmodule Src.Core.AxiomTest do
  use ExUnit.Case

  alias Src.Core.Axiom
  alias Src.Core.Model

  defp sample_model do
    %Model{
      source: "examples/input/chisholm_a1.txt",
      kind: :countermodel,
      cardinality: 2,
      relation_name: "R",
      initial_world: 0,
      edges: MapSet.new([{0, 1}]),
      valuations: %{
        "go" => [true, false]
      },
      warnings: [],
      raw_text: ""
    }
  end

  test "sanitizes Isabelle-compatible names" do
    assert Axiom.sanitize_name("chisholm_a1") == "chisholm_a1"
    assert Axiom.sanitize_name("chisholm-a1.txt") == "chisholm_a1_txt"
    assert Axiom.sanitize_name("123 bad name") == "m_123_bad_name"
    assert Axiom.sanitize_name("!!!") == "nitpick_model"
  end

  test "extracts source stem from model source path" do
    assert Axiom.source_stem(sample_model()) == "chisholm_a1"
  end

  test "uses fallback source stem for text input" do
    model = %Model{sample_model() | source: nil}
    assert Axiom.source_stem(model) == "nitpick_model"
  end

  test "renders exact finite structure formula" do
    formula = Axiom.exact_structure_formula(sample_model())

    assert formula == """
           ¬(R i1 i1) ∧
             (R i1 i2) ∧
             ¬(R i2 i1) ∧
             ¬(R i2 i2) ∧
             (go i1) ∧
             ¬(go i2)\
           """
  end

  test "renders blocking axiom" do
    axiom = Axiom.blocking_axiom(sample_model())

    assert axiom == """
           axiomatization where ax_chisholm_a1: "¬(
             ¬(R i1 i1) ∧
             (R i1 i2) ∧
             ¬(R i2 i1) ∧
             ¬(R i2 i2) ∧
             (go i1) ∧
             ¬(go i2)
           )"\
           """
  end
end
