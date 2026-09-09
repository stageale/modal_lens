defmodule Src.Core.Model.DDL do
  @moduledoc """
  Represents a finite pointed preference model for Dyadic Deontic Logic.

  Worlds are identified by zero-based integer indices. The `actual_world`
  field designates the world at which formulas are evaluated.

  The preference relation is stored in `edges`. An edge `{source, target}`
  means that `source` is at least as good as `target`.

  Proposition valuations map atom names to Boolean lists ordered by world
  index. For example, `%{"p" => [true, false]}` states that `p` holds at world
  `0` but not at world `1`.

  The model cardinality must be supplied when constructing the struct.
  """

  alias Src.Core.ParseWarning

  @typedoc "A zero-based index identifying a world."
  @type world_index :: non_neg_integer()

  @typedoc "A directed edge of the preference relation."
  @type edge :: {world_index(), world_index()}

  @typedoc "The kind of finite structure reported by Nitpick."
  @type result_kind :: :model | :countermodel

  @typedoc "A proposition valuation ordered by world index."
  @type valuation :: [boolean()]

  @typedoc "A finite pointed preference model for Dyadic Deontic Logic."
  @type t :: %__MODULE__{
          source: String.t() | nil,
          kind: result_kind() | nil,
          cardinality: non_neg_integer(),
          relation_name: String.t(),
          actual_world: world_index(),
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
    relation_name: "R",
    actual_world: 0,
    edges: MapSet.new(),
    valuations: %{},
    warnings: [],
    raw_text: ""
  ]
end
