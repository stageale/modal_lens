defmodule Src.TPTP.Include do
  @moduledoc """
  Represents an include directive in a TPTP document.

  The directive identifies another TPTP file and optionally restricts
  which named formulae are imported from it.
  """

  @typedoc """
  Selection of formulae imported from an included TPTP file.
  """
  @type selection :: :all | [String.t()]

  @enforce_keys [:file]

  defstruct [
    :file,
    selection: :all,
    space: nil
  ]

  @typedoc """
  A parsed TPTP include directive.
  """
  @type t :: %__MODULE__{
    file: String.t(),
    selection: selection(),
    space: String.t() | nil
  }

  @doc """
  Creates a TPTP include directive.

  By default, all formulae from the referenced file are selected.
  """
  @spec new(String.t(), selection(), String.t() | nil) :: t()
  def new(file, selection \\ :all, space \\ nil) when is_binary(file) do
    %__MODULE__{
      file: file,
      selection: selection,
      space: space
    }
  end
end
