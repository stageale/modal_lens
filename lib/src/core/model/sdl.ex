defmodule Src.Core.Model.SDL do
  @moduledoc """
  Finite pointed Kripke model for Standard Deontic Logic.
  """

  @enforce_keys [:cardinality]      #!  WHY

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
