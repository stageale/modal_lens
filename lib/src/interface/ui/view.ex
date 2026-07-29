defmodule Src.Interface.Ui.View do
  @moduledoc """
  Projects a UI session into displayable data
  """

  alias Src.Interface.Common.Run
  alias Src.Interface.Ui.Options
  alias Src.Interface.Ui.Session

  @doc "Returns the view for the currently selected options."
  @spec current(Session.t()) :: map()
  def current(%Session{} = session) do
    case Session.current_variant(session) do
      {:ok, variant} ->
        %{
          status: :ready,
          theory_path: session.theory_path,
          options: Options.to_run_params(session.options),
          run: Run.to_map(variant.run),
          result: result_view(variant.result)
        }

      :error ->
        %{
          status: :pending,
          theory_path: session.theory_path,
          options: Options.to_run_params(session.options),
          run: nil,
          result: nil
        }
    end
  end

  @doc "Lists the configurations already calculated in the session."
  @spec available(Session.t()) :: [map()]
  def available(%Session{} = session) do
    Enum.map(session.variants, fn variant ->
      %{
        options: Options.to_run_params(variant.options),
        run_id: variant.run.id,
        status: variant.run.status
      }
    end)
  end

  @doc "Returns all calculated variants in calculation order."
  @spec variants(Session.t()) :: [map()]
  def variants(%Session{} = session) do
    session.variants
    |> Enum.reverse()
    |> Enum.map(fn variant ->
      %{
        options: Options.to_run_params(variant.options),
        run: Run.to_map(variant.run),
        result: result_view(variant.result)
      }
    end)
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
        cluster_verbs:
          Map.get(result, :cluster_verbs, [])
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
      :graph_image_file,
      :blocking_axiom
    ])
  end
end
