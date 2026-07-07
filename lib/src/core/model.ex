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

  def world_indices(%__MODULE__{cardinality: cardinality})
      when is_integer(cardinality) and cardinality > 0 do
    Enum.to_list(0..(cardinality - 1))
  end

  def world_indices(%__MODULE__{}), do: []

  def atom_names(%__MODULE__{} = model) do
    model.valuations
    |> Map.keys()
    |> Enum.sort()
  end

  def warning_messages(%__MODULE__{} = model) do
    Enum.map(model.warnings, fn
      %{message: message} -> message
      warning when is_binary(warning) -> warning
      warning -> inspect(warning)
    end)
  end

  def has_edge(%__MODULE__{edges: edges}, a, b) do
    MapSet.member?(edges, {a, b})
  end

  def edge_count(%__MODULE__{} = model) do
    MapSet.size(model.edges)
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
    for a <- world_indices(model) do
      for b <- world_indices(model) do
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
      edge_count: edge_count(model),
      atoms: atom_names(model),
      warnings: warning_messages(model)
    }
  end
end
