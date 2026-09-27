defmodule Src.Explanation.Visual.GraphViewCatalog do
  @moduledoc "Precomputes graph views for selections of modal relation groups."

  alias Src.Core.Model
  alias Src.Core.Model.EDSTIT
  alias Src.Core.Model.Modality
  alias Src.Explanation.Visual.GraphView
  alias Src.Explanation.Visual.RelationViewBuilder

  @enforce_keys [:filter_keys, :views]
  defstruct [:filter_keys, :views]

  @type t :: %__MODULE__{
          filter_keys: [String.t()],
          views: %{required(String.t()) => GraphView.t()}
        }

  @doc """
  Builds every nonempty selection of the available filter groups.

  Pass `include_empty: true` to also build a view containing worlds but no
  selected relations. The default preserves the existing seven views for
  three filter groups.
  """
  @spec build(EDSTIT.t(), keyword()) :: t()
  def build(%EDSTIT{} = model, opts \\ []) do
    worlds = Model.world_indices(model)
    filter_key = Keyword.get(opts, :filter_key, &default_filter_key/1)

    relations =
      model.modalities
      |> Enum.sort_by(&Modality.sort_key/1)
      |> Enum.map(fn modality ->
        RelationViewBuilder.build(modality, worlds,
          filter_key: filter_key.(modality)
        )
      end)

    filter_keys = relations |> Enum.map(& &1.filter_key) |> Enum.uniq()

    views =
      filter_keys
      |> selections()
      |> Map.new(fn selected ->
        id = selection_id(selected)
        {id, build_view(model, worlds, relations, selected, id)}
      end)

    views =
      if Keyword.get(opts, :include_empty, false) or filter_keys == [] do
        Map.put(views, "none", build_view(model, worlds, relations, [], "none"))
      else
        views
      end

    %__MODULE__{filter_keys: filter_keys, views: views}
  end

  @doc "Returns a precomputed view for a selection of group keys, in any order."
  @spec fetch!(t(), [String.t() | atom()]) :: GraphView.t()
  def fetch!(%__MODULE__{} = catalog, keys) when is_list(keys) do
    requested = keys |> Enum.map(&to_string/1) |> MapSet.new()
    selected = Enum.filter(catalog.filter_keys, &MapSet.member?(requested, &1))

    cond do
      MapSet.size(requested) != length(selected) ->
        invalid_selection!(catalog, keys)

      selected == [] and not Map.has_key?(catalog.views, "none") ->
        invalid_selection!(catalog, keys)

      selected == [] ->
        Map.fetch!(catalog.views, "none")

      true ->
        Map.fetch!(catalog.views, selection_id(selected))
    end
  end

  @doc "Returns the view containing every available group."
  @spec full!(t()) :: GraphView.t()
  def full!(%__MODULE__{filter_keys: [], views: views}),
    do: Map.fetch!(views, "none")

  def full!(%__MODULE__{} = catalog),
    do: fetch!(catalog, catalog.filter_keys)

  defp build_view(model, worlds, relations, selected, id) do
    selected_set = MapSet.new(selected)

    %GraphView{
      id: id,
      model_logic: Model.model_logic(model),
      worlds: worlds,
      designated_world: Model.designated_world(model),
      valuations: model.valuations,
      selected_modalities: selected,
      relations:
        Enum.filter(relations, fn relation ->
          MapSet.member?(selected_set, relation.filter_key)
        end)
    }
  end

  defp invalid_selection!(catalog, keys) do
    raise ArgumentError,
          "unknown or empty modality selection: #{inspect(keys)}; " <>
            "available: #{inspect(catalog.filter_keys)}"
  end

  defp default_filter_key(%Modality{kind: :settledness}), do: :stit
  defp default_filter_key(%Modality{kind: kind}), do: kind

  defp selection_id(keys), do: Enum.join(keys, "+")

  defp selections(keys) do
    Enum.reduce(keys, [], fn key, previous ->
      previous ++ [[key]] ++ Enum.map(previous, &(&1 ++ [key]))
    end)
  end
end
