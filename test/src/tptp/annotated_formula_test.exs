defmodule Src.TPTP.AnnotatedFormulaTest do
  use ExUnit.Case, async: true

  alias Src.TPTP.AnnotatedFormula

  test "creates a minimal THF annotated formula" do
    formula = AnnotatedFormula.new("a1", :axiom, "(p @ a)")

    assert formula == %AnnotatedFormula{
             language: :thf,
             name: "a1",
             role: :axiom,
             formula: "(p @ a)",
             source: nil,
             useful_info: nil
           }
  end

  test "preserves optional TPTP annotations" do
    formula =
      AnnotatedFormula.new(
        "step",
        :plain,
        "(q @ a)",
        "inference(foo,[status(thm)],[a1])",
        "[useful(info)]"
      )

    assert formula.source == "inference(foo,[status(thm)],[a1])"
    assert formula.useful_info == "[useful(info)]"
  end
end
