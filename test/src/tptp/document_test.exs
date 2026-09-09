defmodule Src.TPTP.DocumentTest do
  use ExUnit.Case, async: true

  alias Src.TPTP.AnnotatedFormula
  alias Src.TPTP.Document
  alias Src.TPTP.Include

  test "preserves top-level entry order" do
    axiom = AnnotatedFormula.new("a1", :axiom, "$true")
    include = Include.new("Axioms/base.ax")
    conjecture = AnnotatedFormula.new("c1", :conjecture, "$true")

    document = Document.new([axiom, include, conjecture], "demo.p")

    assert document.source == "demo.p"
    assert document.entries == [axiom, include, conjecture]
  end

  test "filters formulae and includes without changing their order" do
    a1 = AnnotatedFormula.new("a1", :axiom, "$true")
    inc = Include.new("Axioms/base.ax")
    c1 = AnnotatedFormula.new("c1", :conjecture, "$true")
    document = Document.new([a1, inc, c1])

    assert Document.formulas(document) == [a1, c1]
    assert Document.includes(document) == [inc]
  end
end
