defmodule Src.Core.ParseWarning do
  @moduledoc """
  Represents a non-fatal issue encountered while parsing Nitpick output.

  Parse warnings allow the parser to return a usable model even when parts of
  the Nitpick output are missing or cannot be interpreted reliably. Examples
  include an absent designated world, an empty accessibility relation, or a
  requested atom that does not occur in the output.
  """

  @enforce_keys [:message]
  defstruct [:message]

  @typedoc "A non-fatal parser warning with a human-readable message"
  @type t :: %__MODULE__{message: String.t()}
end
