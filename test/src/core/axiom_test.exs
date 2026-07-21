defmodule Src.Core.AxiomTest do
  use ExUnit.Case, async: true

  alias Src.Core.Axiom
  alias Src.Core.BlockingAxiom
  alias Src.Core.Model.SDL

  defp model do
    %SDL{
      source: "examples/chisholm.txt",
      kind: :countermodel,
      cardinality: 1,
      relation_name: "R",
      initial_world: 0,
      edges: MapSet.new([{0, 0}]),
      valuations: %{"go" => [true]}
    }
  end

  test "delegates name and source helpers" do
    assert Axiom.sanitize_name("123 bad-name") ==
             BlockingAxiom.sanitize_name("123 bad-name")

    assert Axiom.source_stem(model()) == BlockingAxiom.source_stem(model())
  end

  test "delegates structure and blocking axiom generation" do
    assert Axiom.exact_structure_formula(model()) ==
             BlockingAxiom.exact_structure_formula(model())

    assert Axiom.blocking_axiom(model(), name: "compat") ==
             BlockingAxiom.blocking_axiom(model(), name: "compat")
  end
end
