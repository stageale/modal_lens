defmodule Src.Core.Model do
  @moduledoc """
  Provides the shared model API forS SDL and DDL countermodels.

  The module acts as a facade over `Src.Core.Model.SDL` and
  `Src.Core.Model.DDL`. It exposes logic-independent operations for inspecting
  worlds, valuations, accessibility relations, warnings, summaries, and
  serialization data.

  World indices are represented internally as zero-based integers. Generated
  Isabelle world names use one-based identifiers such as `i1`, `i2`, and `i3`.
  """

  alias Src.Core.Model.DDL, as: DDLModel
  alias Src.Core.Model.SDL, as: SDLModel

  @typedoc "A model representation supporte by ModalLens"
  @type model :: %SDLModel{} | %DDLModel{}

  @typedoc "The modal logic associated with a model."
  @type model_logic :: :sdl | :ddl

  @typedoc "A zero-based index identifying a world."
  @type world_index :: non_neg_integer()

  @typedoc "A directed relation edge between two worlds."
  @type edge :: {world_index(), world_index()}

  @typedoc "The name of a propositional atom."
  @type atom_name :: String.t()

  @typedoc "A logic-independent summary of a parsed model."
  @type summary :: %{
    required(:source) => String.t(),
    required(:kind) => atom() | nil,
    required(:model_logic) => model_logic(),
    required(:cardinality) => non_neg_integer(),
    required(:relation) => String.t() | nil,
    required(:designated_world) => String.t(),
    required(:edge_count) => non_neg_integer(),
    required(:atoms) => [atom_name()],
    required(:warnings) => [String.t()]
  }

  @typedoc "A string-keyed model representation prepared for serialization."
  @type export_map :: %{String.t() => term()}

  @doc """
  Determines whether `model` is a supported SDL or DDL model.
  """
  @spec supported?(term()) :: boolean()
  def supported?(%SDLModel{}), do: true
  def supported?(%DDLModel{}), do: true
  def supported?(_), do: false

  @doc """
  Returns `model` when it is supported.

  Raises `ArgumentError` when the value is neither an SDL nor a DDL model.
  """
  @spec assert_supported!(term()) :: model()
  def assert_supported!(model) do
    if supported?(model) do
      model
    else
      raise ArgumentError,
            "unsupported countermodel: #{inspect(model)}"
    end
  end

  @doc """
  Returns the logic represented by `model`.
  """
  @spec model_logic(model()) :: model_logic()
  def model_logic(%SDLModel{}), do: :sdl
  def model_logic(%DDLModel{}), do: :ddl

  @doc """
  Returns the zero-based index of the model's designated world.

  For SDL models this is the initial world. For DDL models this is the actual
  world.
  """
  @spec designated_world(model()) :: world_index()
  def designated_world(%SDLModel{initial_world: world}),
    do: world

  def designated_world(%DDLModel{actual_world: world}),
    do: world

  @doc """
  Returns the Isabelle constant used for the designated world.

  SDL models use `"actual_world"`, while DDL models use `"aw"`.
  """
  @spec designated_world_constant(model()) :: String.t()
  def designated_world_constant(%SDLModel{}),
    do: "actual_world"

  def designated_world_constant(%DDLModel{}),
    do: "aw"

  @doc """
  Returns the graph name used when rendering `model`.
  """
  @spec graph_name(model()) :: String.t()
  def graph_name(%SDLModel{}), do: "KripkeModel"
  def graph_name(%DDLModel{}), do: "PreferenceModel"

  @doc """
  Converts a zero-based world index into its generated Isabelle name.

  For example, index `0` becomes `"i1"` and index `2` becomes `"i3"`.
  """
  @spec world_name(model(), integer()) :: String.t()
  def world_name(model, index) when is_integer(index) do
    assert_supported!(model)
    "i#{index + 1}"
  end

  @doc """
  Returns all zero-based world indices declared by `model`.

  A model with cardinality three produces `[0, 1, 2]`. A supported model
  without a positive integer cardinality produces an empty list.
  """
  @spec world_indices(model()) :: [world_index()]
  def world_indices(%{cardinality: cardinality} = model)
      when is_integer(cardinality) and cardinality > 0 do
    assert_supported!(model)
    Enum.to_list(0..(cardinality - 1))
  end

  def world_indices(model) do
    assert_supported!(model)
    []
  end

  @doc """
  Returns the proposition names occurring in `model`, sorted alphabetically.
  """
  @spec atom_names(model()) :: [atom_name()]
  def atom_names(%{valuations: valuations} = model) when is_map(valuations) do
    assert_supported!(model)

    valuations
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Converts the model's parser warnings into readable messages.

  Structured warnings contribute their `:message` field. Existing strings are
  preserved, and other warning values are converted with `inspect/1`.
  """
  @spec warning_messages(model()) :: [String.t()]
  def warning_messages(%{warnings: warnings} = model) do
    assert_supported!(model)
    Enum.map(warnings, fn
      %{message: message} -> message
      warning when is_binary(warning) -> warning
      warning -> inspect(warning)
    end)
  end

  @doc """
  Determines whether the model relation contains the edge `{a, b}`.
  """
  @spec has_edge(model(), world_index(), world_index()) :: boolean()
  def has_edge(%{edges: edges} = model, a, b) do
    assert_supported!(model)
    MapSet.member?(edges, {a, b})
  end

  @doc """
  Returns the number of relation edges in `model`.
  """
  @spec edge_count(model()) :: non_neg_integer()
  def edge_count(%{edges: %MapSet{} = edges} = model) do
    assert_supported!(model)
    MapSet.size(edges)
  end

  @doc """
  Returns all reflexive relation edges of the form `{world, world}`.
  """
  @spec self_loops(model()) :: MapSet.t(edge())
  def self_loops(%{edges: %MapSet{} = edges} = model) do
    assert_supported!(model)
    edges
    |> Enum.filter(fn {a, b} -> a == b end)
    |> MapSet.new()
  end

  @doc """
  Returns all relation edges connecting two distinct worlds.
  """
  @spec proper_edges(model()) :: MapSet.t(edge())
  def proper_edges(%{edges: edges} = model) do
    assert_supported!(model)
    edges
    |> Enum.filter(fn {a, b} -> a != b end)
    |> MapSet.new()
  end

  @doc """
  Builds a display label for a world using all known proposition names.

  True propositions are emitted directly. False propositions are prefixed by
  Isabelle's `\\<not>` symbol. Missing valuations are omitted from the label.

  Passing `nil` as `atoms` selects every proposition in alphabetical order.
  """
  @spec label_for_world(model(), integer(), [atom_name()] | nil) :: String.t()
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

  @doc """
  Returns the model relation as a square Boolean adjacency matrix.

  Rows represent source worlds and columns represent target worlds. Both use
  the order returned by `world_indices/1`.
  """
  def relation_matrix(%{edges: %MapSet{} = edges} = model) do
    assert_supported!(model)
    for a <- world_indices(model) do
      for b <- world_indices(model) do
        MapSet.member?(edges, {a, b})
      end
    end
  end

  @doc """
  Builds a logic-independent summary of `model`.

  The designated world is exposed uniformly through `:designated_world`,
  regardless of whether the concrete model stores it as `:initial_world`
  or `:actual_world`.
  """
  @spec as_summary(model()) :: summary()
  def as_summary(%SDLModel{} = model) do
    %{
      source: model.source || "<text>",
      kind: model.kind,
      model_logic: :sdl,
      cardinality: model.cardinality,
      relation: model.relation_name,
      designated_world:
        world_name(
          model,
          model.initial_world
        ),
      edge_count: edge_count(model),
      atoms: atom_names(model),
      warnings: warning_messages(model)
    }
  end

  def as_summary(%DDLModel{} = model) do
    %{
      source: model.source || "<text>",
      kind: model.kind,
      model_logic: :ddl,
      cardinality: model.cardinality,
      relation: model.relation_name,
      designated_world:
        world_name(
          model,
          model.actual_world
        ),
      edge_count: edge_count(model),
      atoms: atom_names(model),
      warnings: warning_messages(model)
    }
  end

  @doc """
  Converts `model` into a string-keyed map suitable for serialization.

  The export contains the logic, model kind, cardinality, relation,
  designated world, atoms, edges, valuations, warnings, and generated world names.
  """
  @spec to_export_map(model()) :: export_map()
  def to_export_map(model) do
    assert_supported!(model)

    atoms = atom_names(model)
    designated_world = designated_world(model)

    %{
      "logic" =>
        model
        |> model_logic()
        |> Atom.to_string(),
      "kind" => Atom.to_string(model.kind),
      "cardinality" => model.cardinality,
      "relation" => model.relation_name,
      "designated_world" => %{
        "index" => designated_world,
        "name" => world_name(model, designated_world),
        "role" => designated_world_role(model)
      },
      "atoms" => atoms,
      "edges" =>
        model.edges
        |> Enum.sort(),
      "valuations" => model.valuations,
      "warnings" => warning_messages(model),
      "worlds" =>
        model
        |> world_indices()
        |> Enum.map(fn index ->
          %{
            "index" => index,
            "name" => world_name(model, index)
          }
      end)
    }
  end

  @spec designated_world_role(model()) :: String.t()
  defp designated_world_role(%SDLModel{}), do: "initial_world"
  defp designated_world_role(%DDLModel{}), do: "actual_world"
end
