defmodule Src.HardcodedRefinement.FrameStatsTest do
  use ExUnit.Case, async: true

  alias Src.HardcodedRefinement.FrameStats

  describe "from_edges/2" do
    test "computes basic frame statistics" do
      worlds = [:a, :b, :c]

      edges = [
        {:a, :b},
        {:a, :c},
        {:b, :c},
        {:c, :c}
      ]

      stats = FrameStats.from_edges(worlds, edges)

      assert stats.world_count == 3
      assert stats.edge_count == 4
      assert stats.non_loop_edge_count == 3

      assert stats.outdegree == %{
               a: 2,
               b: 1,
               c: 1
             }

      assert stats.length_2_path_count == 4
      assert stats.successor_pair_count == 6
      assert stats.successor_distinct_pair_count == 2

      assert stats.functional_pair_support == 6
      assert stats.functional_pair_violations == 2

      assert stats.functional_excess == 1
      assert stats.functional_excess_support == 6
    end

    test "deduplicates duplicate edges" do
      worlds = [:a, :b]

      edges = [
        {:a, :b},
        {:a, :b},
        {:b, :b}
      ]

      stats = FrameStats.from_edges(worlds, edges)

      assert stats.world_count == 2
      assert stats.edge_count == 2

      assert stats.outdegree == %{
               a: 1,
               b: 1
             }

      assert stats.non_loop_edge_count == 1
    end

    test "adds worlds that occur only in edges" do
      worlds = [:a]

      edges = [
        {:a, :b},
        {:b, :c}
      ]

      stats = FrameStats.from_edges(worlds, edges)

      assert stats.world_count == 3

      assert stats.outdegree == %{
               a: 1,
               b: 1,
               c: 0
             }
    end

    test "handles empty frames" do
      stats = FrameStats.from_edges([], [])

      assert stats.world_count == 0
      assert stats.edge_count == 0
      assert stats.non_loop_edge_count == 0
      assert stats.outdegree == %{}

      assert stats.length_2_path_count == 0
      assert stats.successor_pair_count == 0
      assert stats.successor_distinct_pair_count == 0

      assert stats.functional_pair_support == 0
      assert stats.functional_pair_violations == 0
      assert stats.functional_excess == 0
      assert stats.functional_excess_support == 0
    end
  end
end
