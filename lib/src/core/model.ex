defmodule Src.Core.Model do
  @moduledoc """
  Provides the shared model API for finite models supported by ModalLens.

  The module acts as a facade over `Src.Core.Model.SDL`,
  `Src.Core.Model.DDL`, and `Src.Core.Model.EDSTIT`.

  It exposes logic-independent operations for inspecting worlds,
  valuations, warnings, summaries, and serialization data.

  Operations referring to a single relation, such as `has_edge/3` or
  `relation_matrix/1`, are intentionally restricted to unimodal SDL and
  DDL models. ED-STIТ models instead carry several semantically distinct
  modalities represented by `Src.Core.Model.Modality`.

  World indices are represented internally as zero-based integers.
  Generated Isabelle world names use one-based identifiers such as
  `i1`, `i2`, and `i3`.
  """

  alias Src.Core.Model.DDL, as: DDLModel
  alias Src.Core.Model.EDSTIT, as: EDSTITModel
  alias Src.Core.Model.Modality
  alias Src.Core.Model.SDL, as: SDLModel

  @typedoc "A model representation supported by ModalLens."
  @type model ::
          %SDLModel{}
          | %DDLModel{}
          | %EDSTITModel{}

  @typedoc "A model carrying exactly one accessibility or preference relation."
  @type unimodal_model ::
          %SDLModel{}
          | %DDLModel{}

  @typedoc "The modal logic associated with a model."
  @type model_logic ::
          :sdl
          | :ddl
          | :ed_stit

  @typedoc "A zero-based index identifying a world."
  @type world_index :: non_neg_integer()

  @typedoc "A directed relation edge between two worlds."
  @type edge :: {world_index(), world_index()}

  @typedoc "The name of a propositional atom."
  @type atom_name :: String.t()

  @typedoc "Summary of an SDL or DDL model."
  @type unimodal_summary :: %{
          required(:source) => String.t(),
          required(:kind) => atom() | nil,
          required(:model_logic) => :sdl | :ddl,
          required(:cardinality) => non_neg_integer(),
          required(:relation) => String.t() | nil,
          required(:designated_world) => String.t(),
          required(:edge_count) => non_neg_integer(),
          required(:atoms) => [atom_name()],
          required(:warnings) => [String.t()]
        }

  @typedoc "Summary of an Epistemic Deontic STIT model."
  @type ed_stit_summary :: %{
          required(:source) => String.t(),
          required(:kind) => atom() | nil,
          required(:model_logic) => :ed_stit,
          required(:cardinality) => non_neg_integer(),
          required(:designated_world) => String.t(),
          required(:agents) => [String.t()],
          required(:modality_count) => non_neg_integer(),
          required(:accessibility_count) => non_neg_integer(),
          required(:modalities) => [String.t()],
          required(:atoms) => [atom_name()],
          required(:warnings) => [String.t()]
        }

  @typedoc "Logic-independent summary of a supported finite model."
  @type summary ::
          unimodal_summary()
          | ed_stit_summary()

  @typedoc "A string-keyed model representation prepared for serialization."
  @type export_map :: %{String.t() => term()}

  @doc """
  Determines whether `model` is a supported ModalLens model.
  """
  @spec supported?(term()) :: boolean()
  def supported?(%SDLModel{}), do: true
  def supported?(%DDLModel{}), do: true
  def supported?(%EDSTITModel{}), do: true
  def supported?(_), do: false

  @doc """
  Returns `model` when it is supported.

  Raises `ArgumentError` otherwise.
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
  def model_logic(%EDSTITModel{}), do: :ed_stit

  @doc """
  Returns the zero-based index of the model's designated world.

  For SDL this is the initial world. DDL and ED-STIТ use the actual world.
  """
  @spec designated_world(model()) :: world_index()
  def designated_world(%SDLModel{initial_world: world}),
    do: world

  def designated_world(%DDLModel{actual_world: world}),
    do: world

  def designated_world(%EDSTITModel{actual_world: world}),
    do: world

  @doc """
  Returns the Isabelle constant used for the designated world.
  """
  @spec designated_world_constant(model()) :: String.t()
  def designated_world_constant(%SDLModel{}),
    do: "actual_world"

  def designated_world_constant(%DDLModel{}),
    do: "aw"

  def designated_world_constant(%EDSTITModel{}),
    do: "actual_world"

  @doc """
  Returns the graph name used when rendering `model`.
  """
  @spec graph_name(model()) :: String.t()
  def graph_name(%SDLModel{}), do: "KripkeModel"
  def graph_name(%DDLModel{}), do: "PreferenceModel"
  def graph_name(%EDSTITModel{}), do: "EDSTITModel"

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

  A model with cardinality three produces `[0, 1, 2]`.
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
  def atom_names(%{valuations: valuations} = model)
      when is_map(valuations) do
    assert_supported!(model)

    valuations
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Converts parser warnings into readable messages.
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

  # ---------------------------------------------------------------------------
  # Unimodal relation API
  # ---------------------------------------------------------------------------

  @doc """
  Determines whether the single relation of an SDL or DDL model contains
  the edge `{a, b}`.

  This operation is intentionally not defined for ED-STIТ models because
  accessibility depends on the selected modality.
  """
  @spec has_edge(
          unimodal_model(),
          world_index(),
          world_index()
        ) :: boolean()
  def has_edge(%SDLModel{edges: edges}, a, b) do
    MapSet.member?(edges, {a, b})
  end

  def has_edge(%DDLModel{edges: edges}, a, b) do
    MapSet.member?(edges, {a, b})
  end

  @doc """
  Returns the number of relation edges in an SDL or DDL model.
  """
  @spec edge_count(unimodal_model()) :: non_neg_integer()
  def edge_count(%SDLModel{edges: edges}),
    do: MapSet.size(edges)

  def edge_count(%DDLModel{edges: edges}),
    do: MapSet.size(edges)

  @doc """
  Returns all reflexive relation edges of the form `{world, world}`.
  """
  @spec self_loops(unimodal_model()) :: MapSet.t(edge())
  def self_loops(%SDLModel{edges: edges}),
    do: self_loops_from_edges(edges)

  def self_loops(%DDLModel{edges: edges}),
    do: self_loops_from_edges(edges)

  @doc """
  Returns all relation edges connecting distinct worlds.
  """
  @spec proper_edges(unimodal_model()) :: MapSet.t(edge())
  def proper_edges(%SDLModel{edges: edges}),
    do: proper_edges_from_edges(edges)

  def proper_edges(%DDLModel{edges: edges}),
    do: proper_edges_from_edges(edges)

  @doc """
  Returns the single relation of an SDL or DDL model as a square Boolean
  adjacency matrix.

  Rows represent source worlds and columns represent target worlds.
  """
  @spec relation_matrix(unimodal_model()) :: [[boolean()]]
  def relation_matrix(%SDLModel{edges: edges} = model),
    do: relation_matrix_from_edges(model, edges)

  def relation_matrix(%DDLModel{edges: edges} = model),
    do: relation_matrix_from_edges(model, edges)

  # ---------------------------------------------------------------------------
  # World labels
  # ---------------------------------------------------------------------------

  @doc """
  Builds a display label for a world using known proposition names.

  True propositions are emitted directly. False propositions are prefixed
  by the Unicode negation symbol `¬`. Missing valuations are omitted.

  Passing `nil` as `atoms` selects every proposition alphabetically.
  """
  @spec label_for_world(
          model(),
          integer(),
          [atom_name()] | nil
        ) :: String.t()
  def label_for_world(model, index, atoms \\ nil)

  def label_for_world(
        %{valuations: valuations} = model,
        index,
        nil
      ) do
    assert_supported!(model)

    atoms =
      valuations
      |> Map.keys()
      |> Enum.sort()

    label_for_world(model, index, atoms)
  end

  def label_for_world(
        %{valuations: valuations} = model,
        index,
        atoms
      )
      when is_list(atoms) do
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
              ["¬#{atom}"]
            end
        end
      end)

    case truth_bits do
      [] ->
        label

      bits ->
        "#{label}: #{Enum.join(bits, ", ")}"
    end
  end

  # ---------------------------------------------------------------------------
  # Summaries
  # ---------------------------------------------------------------------------

  @doc """
  Builds a logic-appropriate summary of `model`.
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

  def as_summary(%EDSTITModel{} = model) do
    %{
      source: model.source || "<text>",
      kind: model.kind,
      model_logic: :ed_stit,
      cardinality: model.cardinality,
      designated_world:
        world_name(
          model,
          model.actual_world
        ),
      agents:
        model.agents
        |> Enum.sort(),
      modality_count: length(model.modalities),
      accessibility_count:
        model.modalities
        |> Enum.map(&Modality.accessibility_count/1)
        |> Enum.sum(),
      modalities:
        model.modalities
        |> Enum.sort_by(&Modality.sort_key/1)
        |> Enum.map(&Modality.id/1),
      atoms: atom_names(model),
      warnings: warning_messages(model)
    }
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  @doc """
  Converts `model` into a string-keyed map suitable for serialization.

  SDL and DDL retain the existing single-relation export format.

  ED-STIТ exports an explicit collection of typed modalities, preserving
  their semantic kind, optional agent, backend symbol, and finite
  accessibility interpretation.
  """
  @spec to_export_map(model()) :: export_map()
  def to_export_map(%SDLModel{} = model) do
    to_unimodal_export_map(model)
  end

  def to_export_map(%DDLModel{} = model) do
    to_unimodal_export_map(model)
  end

  def to_export_map(%EDSTITModel{} = model) do
    designated_world = designated_world(model)

    %{
      "logic" => "ed_stit",
      "kind" => export_kind(model.kind),
      "cardinality" => model.cardinality,
      "designated_world" => %{
        "index" => designated_world,
        "name" =>
          world_name(
            model,
            designated_world
          ),
        "role" => "actual_world"
      },
      "agents" =>
        model.agents
        |> Enum.sort(),
      "modalities" =>
        model.modalities
        |> Enum.sort_by(&Modality.sort_key/1)
        |> Enum.map(&modality_to_export_map/1),
      "atoms" => atom_names(model),
      "valuations" => model.valuations,
      "warnings" => warning_messages(model),
      "worlds" => export_worlds(model)
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp to_unimodal_export_map(model) do
    atoms = atom_names(model)
    designated_world = designated_world(model)

    %{
      "logic" =>
        model
        |> model_logic()
        |> Atom.to_string(),
      "kind" => export_kind(model.kind),
      "cardinality" => model.cardinality,
      "relation" => model.relation_name,
      "designated_world" => %{
        "index" => designated_world,
        "name" =>
          world_name(
            model,
            designated_world
          ),
        "role" => designated_world_role(model)
      },
      "atoms" => atoms,
      "edges" =>
        model.edges
        |> Enum.sort(),
      "valuations" => model.valuations,
      "warnings" => warning_messages(model),
      "worlds" => export_worlds(model)
    }
  end

  defp modality_to_export_map(%Modality{} = modality) do
    %{
      "id" => Modality.id(modality),
      "symbol" => modality.symbol,
      "kind" => Atom.to_string(modality.kind),
      "agent" => modality.agent,
      "accessibility" =>
        modality.accessibility
        |> Enum.sort()
    }
  end

  defp export_worlds(model) do
    model
    |> world_indices()
    |> Enum.map(fn index ->
      %{
        "index" => index,
        "name" => world_name(model, index)
      }
    end)
  end

  defp export_kind(nil),
    do: nil

  defp export_kind(kind) when is_atom(kind),
    do: Atom.to_string(kind)

  defp self_loops_from_edges(edges) do
    edges
    |> Enum.filter(fn {a, b} ->
      a == b
    end)
    |> MapSet.new()
  end

  defp proper_edges_from_edges(edges) do
    edges
    |> Enum.filter(fn {a, b} ->
      a != b
    end)
    |> MapSet.new()
  end

  defp relation_matrix_from_edges(model, edges) do
    for a <- world_indices(model) do
      for b <- world_indices(model) do
        MapSet.member?(
          edges,
          {a, b}
        )
      end
    end
  end

  @spec designated_world_role(unimodal_model()) :: String.t()
  defp designated_world_role(%SDLModel{}),
    do: "initial_world"

  defp designated_world_role(%DDLModel{}),
    do: "actual_world"
end
