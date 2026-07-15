defmodule Src.Core.Model do
  alias Src.Core.Model.DDL, as: DDLModel
  alias Src.Core.Model.SDL, as: SDLModel

  def supported?(%SDLModel{}), do: SDLModel
  def supported?(%DDLModel{}), do: DDLModel
  def supported?(_), do: false

  def assert_supported!(model) do
    if supported?(model) do
      model
    else
      raise ArgumentError,
            "unsupported countermodel: #{inspect(model)}"
    end
  end

  def model_logic(%SDLModel{}), do: :sdl
  def model_logic(%DDLModel{}), do: :ddl

  def designated_world(%SDLModel{initial_world: world}),
    do: world

  def designated_world(%DDLModel{actual_world: world}),
    do: world

  def designated_world_constant(%SDLModel{}),
    do: "actual_world"

  def designated_world_constant(%DDLModel{}),
    do: "aw"

  def graph_name(%SDLModel{}), do: "KripkeModel"
  def graph_name(%DDLModel{}), do: "PreferenceModel"

  def world_name(model, index) when is_integer(index) do
    assert_supported!(model)
    "i#{index + 1}"
  end

  def world_indices(%{cardinality: cardinality} = model)
      when is_integer(cardinality) and cardinality > 0 do
    assert_supported!(model)
    Enum.to_list(0..(cardinality - 1))
  end

  def world_indices(model) do
    assert_supported!(model)
    []
  end

  def atom_names(%{valuations: valuations} = model) when is_map(valuations) do
    assert_supported!(model)

    valuations
    |> Map.keys()
    |> Enum.sort()
  end

  def warning_messages(%{warnings: warnings} = model) do
    assert_supported!(model)
    Enum.map(warnings, fn
      %{message: message} -> message
      warning when is_binary(warning) -> warning
      warning -> inspect(warning)
    end)
  end

  def has_edge(%{edges: edges} = model, a, b) do
    assert_supported!(model)
    MapSet.member?(edges, {a, b})
  end

  def edge_count(%{edges: %MapSet{} = edges} = model) do
    assert_supported!(model)
    MapSet.size(edges)
  end

  def self_loops(%{edges: %MapSet{} = edges} = model) do
    assert_supported!(model)
    edges
    |> Enum.filter(fn {a, b} -> a == b end)
    |> MapSet.new()
  end

  def proper_edges(%{edges: edges} = model) do
    assert_supported!(model)
    edges
    |> Enum.filter(fn {a, b} -> a != b end)
    |> MapSet.new()
  end

  def label_for_world(model, index, atoms \\ nil)

  def label_for_world(%{valuations: valuations} = model, index, nil) do
    assert_supported!(model)
    atoms =
      valuations
      |> Map.keys()
      |> Enum.sort()

    label_for_world(model, index, atoms)
  end

  def label_for_world(%{valuations: valuations} = model, index, atoms) when is_list(atoms) do
    assert_supported!(model)
    label = world_name(model, index)

    truth_bits =
      atoms
      |> Enum.flat_map(fn atom ->
        case Map.get(valuations, atom) do
          nil ->
            []

          vals when index >= length(vals) ->
            []

          vals ->
            if Enum.at(vals, index) do
              [atom]
            else
              ["\\<not>#{atom}"]
            end
        end
      end)

    case truth_bits do
      [] -> label
      bits -> "#{label}: #{Enum.join(bits, ", ")}"
    end
  end

  def relation_matrix(%{edges: %MapSet{} = edges} = model) do
    assert_supported!(model)
    for a <- world_indices(model) do
      for b <- world_indices(model) do
        MapSet.member?(edges, {a, b})
      end
    end
  end

  def as_summary(%SDLModel{} = model) do
    common_summary(model)
    |> Map.put(
      :initial_world,
      world_name(model, model.initial_world)
    )
  end

  def as_summary(%DDLModel{} = model) do
    common_summary(model)
    |> Map.put(
      :initial_world,
      world_name(model, model.actual_world)
    )
  end

  defp common_summary(model) do
    %{
      source: model.source || "<text>",
      kind: model.kind,
      model_logic: model_logic(model),
      cardinality: model.cardinality,
      relation: model.relation_name,
      edge_count: edge_count(model),
      atoms: atom_names(model),
      warnings: warning_messages(model)
    }
  end
end
