defmodule FormulaTest do
  use ExUnit.Case, async: true

  test "builds propositional and modal formula strings" do
    assert Formula.neg("p") == "¬(p)"
    assert Formula.conj("p", "q") == "p ∧ q"
    assert Formula.disj("p", "q") == "p ∨ q"
    assert Formula.impl("p", "q") == "p ⟶ q"
    assert Formula.box("r", "p") == "□\\<^sub>rp"
  end

  test "builds Isabelle axiom and edge fragments" do
    assert Formula.axiom("serial", "serial r") ==
             ~s(axiomatization where serial: "serial r")

    assert Formula.edge_formula({1, 3}) == "r w1 w3"
  end

  test "constructs formula structs" do
    formula = %Formula{kind: :atom, args: ["p"]}
    assert formula.kind == :atom
    assert formula.args == ["p"]
  end
end
