defmodule Src.Refinement.SelectionTest do
  @moduledoc """
  Tests deterministic ranking of structural refinement candidates.

  Selection preserves the proposed candidate and imposes no full-cluster
  or zero-outside-support requirement. These tests require no external tools.
  """

  use ExUnit.Case, async: true

  alias Src.Refinement.Selection

  describe "select/1" do
    test "reports an empty candidate list" do
      assert Selection.select([]) == {:error, :no_refinement_candidate}
    end

    test "preserves a proposed candidate with partial and nonzero outside support" do
      proposed = candidate("candidate-1", 0.6, 0.4, 2)

      assert {:ok, ^proposed} = Selection.select([proposed])
    end

    test "higher cluster support takes precedence over every later criterion" do
      preferred = candidate("candidate-z", 0.9, 0.8, 3)
      other = candidate("candidate-a", 0.8, 0.0, 1)

      assert {:ok, ^preferred} = Selection.select([other, preferred])
      assert {:ok, ^preferred} = Selection.select([preferred, other])
    end

    test "lower outside support takes precedence over size and ID on a cluster tie" do
      preferred = candidate("candidate-z", 0.8, 0.1, 3)
      other = candidate("candidate-a", 0.8, 0.2, 1)

      assert {:ok, ^preferred} = Selection.select([other, preferred])
      assert {:ok, ^preferred} = Selection.select([preferred, other])
    end

    test "smaller graphlets take precedence over ID when both supports tie" do
      preferred = candidate("candidate-z", 0.8, 0.2, 2)
      other = candidate("candidate-a", 0.8, 0.2, 3)

      assert {:ok, ^preferred} = Selection.select([other, preferred])
      assert {:ok, ^preferred} = Selection.select([preferred, other])
    end

    test "the final ID tie-breaker is lexicographic and independent of input order" do
      first = candidate("candidate-10", 0.8, 0.2, 2)
      second = candidate("candidate-2", 0.8, 0.2, 2)
      third = candidate("candidate-3", 0.8, 0.2, 2)

      for candidates <- [
            [first, second, third],
            [first, third, second],
            [second, first, third],
            [second, third, first],
            [third, first, second],
            [third, second, first]
          ] do
        assert {:ok, ^first} = Selection.select(candidates)
      end
    end

    test "rejects malformed entries instead of silently selecting a valid alternative" do
      valid = candidate("candidate-1", 0.8, 0.2, 2)

      for invalid <- [
            %{},
            Map.put(valid, "schema_version", "2.0"),
            Map.put(valid, "candidate_id", " "),
            put_in(valid, ["origin", "cluster_support"], "0.8"),
            put_in(valid, ["occurrence", "size"], 0)
          ] do
        assert Selection.select([valid, invalid]) ==
                 {:error, {:invalid_candidate, invalid}}

        assert Selection.select([invalid, valid]) ==
                 {:error, {:invalid_candidate, invalid}}
      end
    end

    test "reports a null candidate through the error contract" do
      valid = candidate("candidate-1", 0.8, 0.2, 2)

      for candidates <- [[nil], [valid, nil], [nil, valid]] do
        assert Selection.select(candidates) == {:error, {:invalid_candidate, nil}}
      end
    end

    test "rejects inputs that are not candidate lists" do
      for invalid <- [nil, %{}, "candidate-1", 1] do
        assert Selection.select(invalid) == {:error, {:invalid_options, invalid}}
      end
    end
  end

  # Build complete candidate payloads so successful selection also checks
  # that the occurrence, origin and refinement data survive unchanged.
  @spec candidate(String.t(), number(), number(), pos_integer()) :: Selection.candidate()
  defp candidate(id, cluster_support, outside_support, size) do
    world_ids = Enum.map(1..size, &"u#{&1}")

    %{
      "schema" => "modal-lens/refinement-candidate",
      "schema_version" => "1.0",
      "candidate_id" => id,
      "kind" => "exact_induced_graphlet_exclusion",
      "status" => "candidate",
      "origin" => %{
        "pattern_id" => "cluster-0-pattern-1",
        "cluster_id" => 0,
        "rank" => 1,
        "cluster_support" => cluster_support,
        "outside_support" => outside_support,
        "contrast" => cluster_support - outside_support
      },
      "occurrence" => %{
        "size" => size,
        "pairwise_distinct" => true,
        "worlds" =>
          Enum.map(world_ids, fn id ->
            %{"id" => id, "valuations" => %{"p" => true}}
          end),
        "relation_cells" =>
          for source <- world_ids, target <- world_ids do
            %{
              "source" => source,
              "target" => target,
              "relation" => "R",
              "holds" => source == target
            }
          end
      },
      "refinement" => %{
        "rule" => "exclude_exact_induced_occurrence",
        "operator" => "not",
        "operand" => "occurrence"
      }
    }
  end
end
