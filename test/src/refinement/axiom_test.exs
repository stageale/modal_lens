Code.require_file("../../support/refinement_helpers.exs", __DIR__)

defmodule Src.Refinement.AxiomTest do
  @moduledoc "Tests exact induced occurrences and their structural negation."
  use ExUnit.Case, async: true
  alias Src.Refinement.{Axiom, TestSupport}

  test "renders every internal relation and valuation with distinct witnesses" do
    formula = Axiom.occurrence_formula(TestSupport.candidate())
    expected = ~S"""
    \<exists>u1 u2.
      distinct [u1, u2] \<and>
      \<not> (R u1 u1) \<and>
      R u1 u2 \<and>
      \<not> (R u2 u1) \<and>
      \<not> (R u2 u2) \<and>
      p u1 \<and>
      \<not> (q u1) \<and>
      \<not> (p u2) \<and>
      \<not> (q u2)
    """
    assert normalize(formula) == normalize(expected)
    refute formula =~ ~S(\<forall>)
    refute formula =~ "UNIV"
  end

  test "supports a third world and an empty proposition signature" do
    candidate = TestSupport.candidate(size: 3)
    candidate = update_in(candidate, ["occurrence", "worlds"], fn worlds ->
      Enum.map(worlds, &Map.put(&1, "valuations", %{}))
    end)
    formula = Axiom.occurrence_formula(candidate)
    assert formula =~ ~S(\<exists>u1 u2 u3.)
    assert formula =~ "distinct [u1, u2, u3]"
    assert length(Regex.scan(~r/R u[123] u[123]/, formula)) == 9
    refute formula =~ ~S(\<forall>)
  end

  test "canonicalizes relation-cell ordering" do
    candidate = TestSupport.candidate()
    reordered = update_in(candidate, ["occurrence", "relation_cells"], &Enum.reverse/1)
    assert Axiom.refinement_axiom(candidate) == Axiom.refinement_axiom(reordered)
  end

  test "rejects missing and duplicate cells instead of weakening an induced pattern" do
    candidate = TestSupport.candidate()
    cells = candidate["occurrence"]["relation_cells"]
    for invalid <- [Enum.drop(cells, 1), [hd(cells) | Enum.drop(cells, -1)]] do
      assert_raise ArgumentError, fn ->
        Axiom.occurrence_formula(put_in(candidate, ["occurrence", "relation_cells"], invalid))
      end
    end
  end

  test "rejects unequal valuation signatures and non-distinct world IDs" do
    candidate = TestSupport.candidate()
    [first, second] = candidate["occurrence"]["worlds"]
    for worlds <- [
          [first, Map.put(second, "valuations", %{"p" => false})],
          [first, Map.put(second, "id", first["id"])]
        ] do
      assert_raise ArgumentError, fn ->
        Axiom.occurrence_formula(put_in(candidate, ["occurrence", "worlds"], worlds))
      end
    end
  end

  test "rejects mixed relations and unsafe proposition identifiers" do
    candidate = TestSupport.candidate()
    mixed = update_in(candidate, ["occurrence", "relation_cells"], fn [first | rest] ->
      [Map.put(first, "relation", "S") | rest]
    end)
    unsafe = update_in(candidate, ["occurrence", "worlds"], fn worlds ->
      Enum.map(worlds, &Map.put(&1, "valuations", %{"p) OR True" => true}))
    end)
    for invalid <- [mixed, unsafe] do
      assert_raise ArgumentError, fn -> Axiom.refinement_axiom(invalid) end
    end
  end

  test "negates the complete occurrence and uses the requested axiom name" do
    candidate = TestSupport.candidate()
    occurrence = Axiom.occurrence_formula(candidate)
    refinement = Axiom.refinement_formula(candidate)

    assert refinement =~ "\\<not> ("
    assert normalize(refinement) =~ normalize(occurrence)

    axiom = Axiom.refinement_axiom(candidate, name: "round-2 chosen")
    assert axiom =~ "axiomatization where"
    assert axiom =~ "ax_round_2_chosen:"
    assert axiom =~ "\\<not> ("
  end

  @spec normalize(String.t()) :: String.t()
  defp normalize(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()
end
