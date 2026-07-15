defmodule Src.Core.Model.DDL do
  @moduledoc """
  Finite pointed preference model for Dyadic Deontic Logic.

  `edges` represents the betterness relation R.
  `{a, b}` means that world ais at least as good as world b.
  """

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
