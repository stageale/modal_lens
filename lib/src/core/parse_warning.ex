defmodule Src.Core.ParseWarning do
  @moduledoc """
  Describes a non-fatal issue encountered while parsing Nitpick output
  """

  @enforce_keys [:message]
  defstruct [:message]

  @type t :: %__MODULE__{message: String.t()}
end
