defmodule Src.TPTP.Document do
  @moduledoc """
  Represents a parsed TPTP document.

  A document prserves the order of annotated formulae and include
  directives without interpreting their logical content.
  """

  alias Src.TPTP.AnnotatedFormula
  alias Src.TPTP.Include

  @typedoc """
  A top-level entry in a TPTP document.
  """
  @type entry :: AnnotatedFormula.t() | Include.t()

  defstruct [
    :source,
    entries: []
  ]

  @typedoc """
  A parsed TPTP document with optional source information.
  """
  @type t :: %__MODULE__{
    source: String.t() | nil,
    entries: [entry()]
  }

  @doc """
  Creates a TPTP document.

  The source identifies the origin of the document, if known.
  """
  @spec new([entry()], String.t() | nil) :: t()
  def new(entries \\ [], source \\ nil) when is_list(entries) do
    %__MODULE__{
      source: source,
      entries: entries
    }
  end

  @doc """
  Returns all annotated formulae in document order.
  """
  @spec formulas(t()) :: [AnnotatedFormula.t()]
  def formulas(%__MODULE__{entries: entries}) do
    Enum.filter(entries, &match?(%AnnotatedFormula{}, &1))
  end

  @doc """
  Returns all include directives in document order.
  """
  @spec includes(t()) :: [Include.t()]
  def includes(%__MODULE__{entries: entries}) do
    Enum.filter(entries, &match?(%Include{}, &1))
  end
end
