defmodule Src.Explanation.Visual.PreferenceLayers do
  @moduledoc """
  Visual explanation of a finite DDL preference relation as ordered layers.

  The DDL relation follows the convention used by `Src.Core.Model.DDL`:
  an edge `{source, target}` means that `source` is at least as good as
  `target`.

  For finite total preorders, worlds can therefore be arranged into
  indifference layers. Layer 0 contains the optimal worlds, subsequent
  layers contain increasingly less preferred worlds.

  This module does not modify or complete the relation. It only derives
  a visual explanation when the supplied relation satisfies the expected
  total-preorder conditions.
  """

  alias Src.Core.Model
  alias Src.Core.Model.DDL

  @type world :: non_neg_integer()

  @type layer :: %{
          rank: non_neg_integer(),
          worlds: [world()]
        }

  defstruct layers: [],
            world_layers: %{},
            optimal_worlds: [],
            actual_world: nil,
            actual_world_layer: nil

  @type t :: %__MODULE__{
          layers: [layer()],
          world_layers: %{optional(world()) => non_neg_integer()},
          optimal_worlds: [world()],
          actual_world: world() | nil,
          actual_world_layer: non_neg_integer() | nil
        }

  @doc """
  Builds a preference-layer explanation for a finite DDL model.

  Returns an error when the relation is not a total preorder.
  """
  @spec from_model(DDL.t()) :: {:ok, t()} | {:error, term()}
  def from_model(%DDL{} = model) do
    with :ok <- validate_reflexive(model),
         :ok <- validate_total(model),
         :ok <- validate_transitive(model),
         {:ok, layers} <- build_layers(model) do
      world_layers =
        layers
        |> Enum.flat_map(fn %{rank: rank, worlds: worlds} ->
          Enum.map(worlds, &{&1, rank})
        end)
        |> Map.new()

      actual_world_layer =
        Map.fetch!(world_layers, model.actual_world)

      {:ok,
       %__MODULE__{
         layers: layers,
         world_layers: world_layers,
         optimal_worlds:
           layers
           |> hd()
           |> Map.fetch!(:worlds),
         actual_world: model.actual_world,
         actual_world_layer: actual_world_layer
       }}
    end
  end

  @doc """
  Returns the layer containing a world.
  """
  @spec layer_of(t(), world()) :: non_neg_integer() | nil
  def layer_of(%__MODULE__{} = explanation, world) do
    Map.get(explanation.world_layers, world)
  end

  @doc """
  Returns true when the world belongs to the optimal layer.
  """
  @spec optimal?(t(), world()) :: boolean()
  def optimal?(%__MODULE__{} = explanation, world) do
    world in explanation.optimal_worlds
  end

  defp validate_reflexive(%DDL{} = model) do
    case Enum.find(Model.world_indices(model), fn world ->
           not Model.has_edge(model, world, world)
         end) do
      nil ->
        :ok

      world ->
        {:error, {:preference_relation_not_reflexive, {world, world}}}
    end
  end

  defp validate_total(%DDL{} = model) do
    worlds = Model.world_indices(model)

    witness =
      (for left <- worlds,
           right <- worlds,
           left < right,
           not Model.has_edge(model, left, right),
           not Model.has_edge(model, right, left),
           do: {left, right})
      |> List.first()

    case witness do
      nil ->
        :ok

      pair ->
        {:error, {:preference_relation_not_total, pair}}
    end
  end

  defp validate_transitive(%DDL{} = model) do
    worlds = Model.world_indices(model)

    witness =
      (for left <- worlds,
           middle <- worlds,
           right <- worlds,
           Model.has_edge(model, left, middle),
           Model.has_edge(model, middle, right),
           not Model.has_edge(model, left, right),
           do: {left, middle, right})
      |> List.first()

    case witness do
      nil ->
        :ok

      triple ->
        {:error, {:preference_relation_not_transitive, triple}}
    end
  end

  defp build_layers(%DDL{} = model) do
    remaining =
      model
      |> Model.world_indices()
      |> MapSet.new()

    peel_layers(model, remaining, 0, [])
  end

  defp peel_layers(%DDL{} = model, remaining, rank, layers) do
    if MapSet.size(remaining) == 0 do
      {:ok, Enum.reverse(layers)}
    else
      peel_next_layers(model, remaining, rank, layers)
    end
  end

  defp peel_next_layers(%DDL{} = model, remaining, rank, layers) do
    optimal_worlds =
      remaining
      |> Enum.filter(fn candidate ->
        Enum.all?(remaining, fn other ->
          Model.has_edge(model, candidate, other)
        end)
      end)
      |> Enum.sort()

    case optimal_worlds do
      [] ->
        {:error, {:preference_layer_construction_failed, Enum.sort(remaining)}}

      worlds ->
        remaining =
          Enum.reduce(worlds, remaining, fn world, acc ->
            MapSet.delete(acc, world)
          end)

        layer = %{
          rank: rank,
          worlds: worlds
        }

        peel_layers(
          model,
          remaining,
          rank + 1,
          [layer | layers]
        )
    end
  end
end
