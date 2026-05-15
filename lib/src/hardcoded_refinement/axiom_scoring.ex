defmodule Src.HardcodedRefinement.AxiomScoring do
  alias Src.HardcodedRefinement.FrameAnalysis
  alias Src.HardcodedRefinement.FrameStats

  @default_weights %{
    serial: 1.0,
    reflexive: 1.0,
    symmetric: 1.0,
    transitive: 1.4,
    euclidean: 1.3,
    functional: 1.2
  }

  def ranked_suggestions(%FrameAnalysis{} = analysis, worlds, edges, opts \\ []) do
    stats = FrameStats.from_edges(worlds, edges)
    ranked_suggestions_from_stats(analysis, stats, opts)
  end

  def ranked_suggestions_from_stats(%FrameAnalysis{} = analysis, %FrameStats{} = stats, opts) do
    weights = Keyword.get(opts, :weights, @default_weights)

    analysis
    |> metrics(stats, opts)
    |> Enum.map(fn metric -> add_score(metric, weights) end)
    |> Enum.sort_by(fn metric -> metric.score end, :desc)
  end

  def metrics(%FrameAnalysis{} = analysis, stats, opts \\ []) do
    euclidean_mode = Keyword.get(opts, :euclidean_mode, :all_pairs)
    functional_mode = Keyword.get(opts, :functional_mode, :pairs)

    euclidean_support =
      case euclidean_mode do
        :all_pairs -> stats.successor_pair_count
        :distinct_pairs -> stats.successor_distinct_pair_count
      end

    functional_measure =
      case functional_mode do
        :pairs ->
          %{
            violations: stats.functional_pair_violations,
            support: stats.functional_pair_support
          }

        :excess ->
          %{
            violations: stats.functional_excess,
            support: stats.functional_excess_support
          }

        :analysis_worlds ->
          %{
            violations: MapSet.size(analysis.function_violations),
            support: stats.world_count
          }
      end

    [
      metric(:serial, length(analysis.dead_ends), stats.world_count),
      metric(:reflexive, length(analysis.missing_loops), stats.world_count),
      metric(:symmetric, length(analysis.antisymmetries), stats.non_loop_edge_count),
      metric(:transitive, length(analysis.missing_hulls), stats.length_2_path_count),
      metric(:euclidean, length(analysis.missing_spans), euclidean_support),
      metric(:functional, functional_measure.violations, functional_measure.support)
    ]
  end

  defp metric(axiom, violations, support) do
    %{
      axiom: axiom,
      violations: violations,
      support: support,
      density: safe_div(violations, support)
    }
  end

  defp add_score(%{axiom: axiom, density: density, support: support} = metric, weights) do
    weight = Map.get(weights, axiom, 1.0)
    support_boost = support_boost(support)

    Map.merge(metric, %{
      weight: weight,
      support_boost: support_boost,
      score: weight * density * support_boost
    })
  end

  defp support_boost(support) when support <= 0, do: 0.0

  defp support_boost(support) do
    :math.log(1.0 + support)
  end

  defp safe_div(_x, 0), do: 0.0
  defp safe_div(x, y), do: x / y
end
