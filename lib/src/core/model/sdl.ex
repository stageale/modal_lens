defmodule Src.Core.Model.SDL do
  @moduledoc """
  Finite pointed Kripke model for Standard Deontic Logic.
  """

  alias Src.Core.ParseWarning

  @typedoc "A zero-based index identifying a world."
  @type world_index :: non_neg_integer()

  @typedoc "A directed accessibility edge between two worlds."
  @type edge :: {world_index(), world_index()}

  @typedoc "The kind of finite structure reported by Nitpick."
  @type result_kind :: :model | :countermodel

  @typedoc "A proposition valuation ordered by world index."
  @type valuation :: [boolean()]

  @typedoc "A finite pointed Kripke model for Standard Deontic Logic."
  @type t :: %__MODULE__{
          source: String.t() | nil,
          kind: result_kind() | nil,
          cardinality: non_neg_integer(),
          relation_name: String.t() | nil,
          initial_world: world_index(),
          edges: MapSet.t(edge()),
          valuations: %{optional(String.t()) => valuation()},
          warnings: [ParseWarning.t()],
          raw_text: String.t()
        }


  @enforce_keys [:cardinality]

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
end
