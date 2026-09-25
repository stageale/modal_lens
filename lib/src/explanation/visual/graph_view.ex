defmodule Src.Explanation.Visual.GraphView do
  @moduledoc """
  Materialized visualization view over a finite modal model.

  A graph view is derived presentation data. It never replaces or mutates
  the underlying logical model. The same model may therefore have several
  precomputed graph views containing different selections of modalities.

  Relations retain both their original directed edges and the edges
  prepared for display. This duplication keeps the logical source data
  available to later visualization passes and interactive frontends while
  allowing the displayed graph to be simplified independently.
  """

  alias Src.Explanation.Visual.GraphView.RelationView

  @typedoc "A zero-based world index."
  @type world_index :: non_neg_integer()

  @typedoc "Stable key of a modality exposed by the visualization filter."
  @type modality_key :: String.t()

  @type t :: %__MODULE__{
    id: String.t(),
    model_logic: atom(),
    worlds: [world_index()],
    designated_world: world_index(),
    valuations: %{optional(String.t()) => [boolean()]},
    selected_modalities: [modality_key()],
    relations: [RelationView.t()]
  }

  @enforce_keys [
    :id,
    :model_logic,
    :worlds,
    :designated_world,
    :valuations,
    :selected_modalities,
    :relations
  ]

  defstruct [
    :id,
    :model_logic,
    :worlds,
    :designated_world,
    :valuations,
    selected_modalities: [],
    relations: []
  ]

  defmodule RelationView do
    @moduledoc """
    Materialized visualization state for one concrete modal relation.

    `filter_key` identifies the option in the modality filter to which this
    relation belongs. Several concrete relations may share a filter key; for
    example, STIT relations of different agents may all use `"stit"`.

    `original_edges` is an unchanged copy of the relation found in the model.
    `edges` contains only the derived representation used by the graph view.
    """

    alias Src.Explanation.Visual.GraphView.ViewEdge

    @typedoc "Structural properties computed on the original relation."
    @type properties :: %{
      required(:reflexive) => boolean(),
      required(:symmetric) => boolean(),
      required(:transitive) => boolean()
    }

    @type t :: %__MODULE__{
      modality_id: String.t(),
      filter_key: String.t(),
      symbol: String.t(),
      kind: atom(),
      agent: String.t() | nil,
      original_edges: MapSet.t({non_neg_integer(), non_neg_integer()}),
      edges: [ViewEdge.t()],
      properties: properties() | nil
    }

    @enforce_keys [
      :modality_id,
      :filter_key,
      :symbol,
      :kind,
      :original_edges,
      :edges
    ]

    defstruct [
      :modality_id,
      :filter_key,
      :symbol,
      :kind,
      :agent,
      :original_edges,
      :properties,
      edges: []
    ]
  end

  defmodule ViewEdge do
    @moduledoc """
    Edge used by a graph view.

    Directions are presentation semantics:

      * `:forward` represents one directed edge,
      * `:both` represents a reciprocal pair collapsed into one edge with
        arrowheads at both ends,
      * `:undirected` is available when a relation is globally symmetric and
        direction no longer needs to be rendered explicitly.
    """

    @type direction :: :forward | :both | :undirected

    @type t :: %__MODULE__{
      source: non_neg_integer(),
      target: non_neg_integer(),
      direction: direction()
    }

    @enforce_keys [:source, :target, :direction]

    defstruct [
      :source,
      :target,
      :direction
    ]
  end

end
