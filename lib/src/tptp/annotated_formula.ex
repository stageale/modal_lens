defmodule Src.TPTP.AnnotatedFormula do
  @moduledoc """
  Represents a single annotated THF formula in a TPTP document.

  This module models the syntactic TPTP record only and does not
  interpret the contained logical formula.
  """

  @typedoc """
  TPTP language supported by the current ModalLens frontend.
  """
  @type language :: :thf

  @typedoc """
  Standard TPTP role assigned to an annotated formula.
  """
  @type role :: :axiom
              | :hypothesis
              | :definition
              | :assumption
              | :lemma
              | :theorem
              | :corollary
              | :conjecture
              | :negated_conjecture
              | :plain
              | :type
              | :interpretation
              | :logic
              | :unknown

  @enforce_keys [:language, :name, :role, :formula]
  defstruct [
    :language,
    :name,
    :role,
    :formula,
    :source,
    :useful_info
  ]

  @typedoc """
  A parsed THF annotated-formula record
  """
  @type t :: %__MODULE__{
    language: language(),
    name: String.t(),
    role: role(),
    formula: String.t(),
    source: String.t() | nil,
    useful_info: String.t() | nil
  }

  @doc """
  Creates an annotated THF formula without optional annotations.
  """
  @spec new(String.t(), role(), String.t()) :: t()
  def new(name, role, formula) when is_binary(name) and is_binary(formula) do
    %__MODULE__{
      language: :thf,
      name: name,
      role: role,
      formula: formula
    }
  end

  @doc """
  Creates an annotated THF formula including optional TPTP annotations.
  """
  @spec new(String.t(), role(), String.t(), String.t() | nil, String.t() | nil) :: t()
  def new(name, role, formula, source, useful_info) when is_binary(name) and is_binary(formula) do
    %__MODULE__{
      language: :thf,
      name: name,
      role: role,
      formula: formula,
      source: source,
      useful_info: useful_info
    }
  end
end
