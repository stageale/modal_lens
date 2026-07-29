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
          result: variant.result
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
    Map.take(result, [
      :status,
      :iteration,
      :theory_name,
      :model_summary,
      :worlds,
      :warnings,
      :graph_image_file,
      :blocking_axiom,
      :llm_explanation,
      :llm_metadata
    ])
  end
end
