defmodule Src.Core.Model do
  defstruct [
    :source,
    :kind,
    :cardinality,
    :relation_name,
    initial_world: 0,
    edges: MapSet.new(),
    valuations: %{},
    warnings: [],
    raw_text: ""
  ]

  def world_name(%__MODULE__{}, index) when is_integer(index) do
    "i#{index + 1}"
  end

  def has_edge(%__MODULE__{edges: edges}, a, b) do
    MapSet.member?(edges, {a, b})
  end

  def self_loops(%__MODULE__{edges: edges}) do
    edges
    |> Enum.filter(fn {a, b} -> a == b end)
    |> MapSet.new()
  end

  def proper_edges(%__MODULE__{edges: edges}) do
    edges
    |> Enum.filter(fn {a, b} -> a != b end)
    |> MapSet.new()
  end

  def label_for_world(model, index, atoms \\ nil)

  def label_for_world(%__MODULE__{} = model, index, nil) do
    atoms =
      model.valuations
      |> Map.keys()
      |> Enum.sort()

    label_for_world(model, index, atoms)
  end

  def label_for_world(%__MODULE__{} = model, index, atoms) when is_list(atoms) do
    label = world_name(model, index)

    truth_bits =
      atoms
      |> Enum.flat_map(fn atom ->
        case Map.get(model.valuations, atom) do
          nil ->
            []

          vals when index >= length(vals) ->
            []

          vals ->
            if Enum.at(vals, index) do
              [atom]
            else
              ["¬#{atom}"]
            end
        end
      end)

    case truth_bits do
      [] -> label
      bits -> "#{label}: #{Enum.join(bits, ", ")}"
    end
  end

  def relation_matrix(%__MODULE__{} = model) do
    for a <- 0..(model.cardinality - 1) do
      for b <- 0..(model.cardinality - 1) do
        MapSet.member?(model.edges, {a, b})
      end
    end
  end

  def as_summary(%__MODULE__{} = model) do
    %{
      source: model.source || "<text>",
      kind: model.kind,
      cardinality: model.cardinality,
      relation: model.relation_name,
      initial_world: world_name(model, model.initial_world),
      edge_count: MapSet.size(model.edges),
      atoms: model.valuations |> Map.keys() |> Enum.sort(),
      warnings: Enum.map(model.warnings, fn warning -> Map.get(warning, :message) end)
    }
  end
end
