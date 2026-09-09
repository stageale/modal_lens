defmodule Src.Interface.Ui.View do
  @moduledoc """
  Projects calculated UI variants into data consumed by the HTML page.
  """

  alias Src.Execution.Options
  alias Src.Execution.Run
  alias Src.Interface.Ui.Session

  @doc "Returns all calculated variants in their execution order."
  @spec variants(Session.t()) :: [map()]
  def variants(%Session{} = session) do
    session.variants
    |> Enum.reverse()
    |> Enum.map(fn variant ->
      %{
        options: Options.to_run_params(variant.options),
        run: Run.to_map(variant.run),
        stage: Map.get(variant, :stage),
        refinement: refinement_view(Map.get(variant, :refinement)),
        result: result_view(variant.result)
      }
    end)
  end

  defp refinement_view(nil), do: nil

  defp refinement_view(refinement) when is_map(refinement) do
    candidate = Map.get(refinement, :candidate, %{})
    origin = Map.get(candidate, "origin", %{})
    occurrence = Map.get(candidate, "occurrence", %{})

    %{
      round: Map.get(refinement, :round),
      input_theory_path: Map.get(refinement, :input_theory_path),
      refined_theory_path: Map.get(refinement, :refined_theory_path),
      candidate_id: Map.get(candidate, "candidate_id"),
      pattern_id: Map.get(origin, "pattern_id"),
      cluster_id: Map.get(origin, "cluster_id"),
      cluster_support: Map.get(origin, "cluster_support"),
      outside_support: Map.get(origin, "outside_support"),
      contrast: Map.get(origin, "contrast"),
      graphlet_size: Map.get(occurrence, "size"),
      axiom: Map.get(refinement, :axiom),
      candidate: candidate
    }
  end

  defp result_view(result) do
    %{
      status: Map.get(result, :status),
      model_count: Map.get(result, :model_count) || length(Map.get(result, :models, [])),
      graph_analysis: Map.get(result, :graph_analysis, %{}),
      clusters:
        result
        |> Map.get(:clusters, [])
        |> Enum.map(&cluster_view/1),
      cluster_verbs: Map.get(result, :cluster_verbs, [])
    }
  end

  defp cluster_view(cluster) do
    %{
      cluster_id: Map.get(cluster, :cluster_id),
      model_count: Map.get(cluster, :model_count),
      model_fraction: Map.get(cluster, :model_fraction),
      characteristic_patterns: Map.get(cluster, :characteristic_patterns, []),
      models:
        cluster
        |> Map.get(:models, [])
        |> Enum.map(&model_view/1)
    }
  end

  defp model_view(model) do
    Map.take(model, [
      :iteration,
      :cluster_id,
      :theory_name,
      :model_summary,
      :worlds,
      :warnings,
      :graph_svg_file,
      :graph_tikz_file,
      :graph_pdf_file,
      :blocking_axiom
    ])
  end
end
