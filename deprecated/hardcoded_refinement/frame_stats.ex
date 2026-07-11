defmodule Src.HardcodedRefinement.FrameStats do
  defstruct [
    :world_count,
    :edge_count,
    :non_loop_edge_count,
    :outdegree,
    :length_2_path_count,
    :successor_pair_count,
    :successor_distinct_pair_count,
    :functional_pair_support,
    :functional_pair_violations,
    :functional_excess,
    :functional_excess_support
  ]

  def from_edges(worlds, edges) do
    edge_set = MapSet.new(edges)
    worlds = complete_worlds(worlds, edge_set)

    successors =
      worlds
      |> Enum.map(fn w -> {w, MapSet.new()} end)
      |> Map.new()

    successors =
      Enum.reduce(edge_set, successors, fn {w, v}, acc ->
        Map.update(acc, w, MapSet.new([v]), fn old ->
          MapSet.put(old, v)
        end)
      end)

    outdegree =
      successors
      |> Enum.map(fn {w, succs} -> {w, MapSet.size(succs)} end)
      |> Map.new()

    %__MODULE__{
      world_count: length(worlds),
      edge_count: MapSet.size(edge_set),
      non_loop_edge_count: non_loop_edge_count(edge_set),
      outdegree: outdegree,
      length_2_path_count: length_2_path_count(edge_set, outdegree),
      successor_pair_count: successor_pair_count(outdegree),
      successor_distinct_pair_count: successor_distinct_pair_count(outdegree),
      functional_pair_support: functional_pair_support(outdegree),
      functional_pair_violations: functional_pair_violations(outdegree),
      functional_excess: functional_excess(outdegree),
      functional_excess_support: functional_excess_support(length(worlds))
    }
  end

  defp complete_worlds(worlds, edge_set) do
    edge_worlds =
      edge_set
      |> Enum.flat_map(fn {w, v} -> [w, v] end)

    worlds
    |> Enum.concat(edge_worlds)
    |> Enum.uniq()
  end

  defp non_loop_edge_count(edge_set) do
    Enum.count(edge_set, fn {w, v} -> w != v end)
  end

  # Active obligations for transitivity:
  #
  # R w u && R u v -> R w v
  #
  # For every edge w -> u, the number of continuations is outdegree(u).
  defp length_2_path_count(edge_set, outdegree) do
    Enum.reduce(edge_set, 0, fn {_w, u}, acc ->
      acc + Map.get(outdegree, u, 0)
    end)
  end

  # Active obligations for Euclideanness:
  #
  # R w u && R w v -> R u v
  #
  # This includes u = v because the axiom itself does not exclude it.
  defp successor_pair_count(outdegree) do
    outdegree
    |> Map.values()
    |> Enum.reduce(0, fn d, acc -> acc + d * d end)
  end

  # Variant excluding u = v.
  defp successor_distinct_pair_count(outdegree) do
    outdegree
    |> Map.values()
    |> Enum.reduce(0, fn d, acc -> acc + d * max(d - 1, 0) end)
  end

  # For functionality:
  #
  # R w u && R w v -> u = v
  #
  # If u and v are distinct successors, this is a violation.
  # We count ordered pairs here, matching the universal variables u and v.
  defp functional_pair_support(outdegree) do
    successor_pair_count(outdegree)
  end

  defp functional_pair_violations(outdegree) do
    outdegree
    |> Map.values()
    |> Enum.reduce(0, fn d, acc -> acc + d * max(d - 1, 0) end)
  end

  # Softer alternative:
  #
  # A world with 3 successors has excess 2, not 6.
  defp functional_excess(outdegree) do
    outdegree
    |> Map.values()
    |> Enum.reduce(0, fn d, acc -> acc + max(d - 1, 0) end)
  end

  defp functional_excess_support(n) do
    n * max(n - 1, 0)
  end
end
