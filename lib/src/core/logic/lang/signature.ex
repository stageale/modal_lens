defmodule Src.Core.Logic.Lang.Signature do
  @moduledoc """
  Collects the non-logical symbols of a component language.

  A signature does not assign concrete denotations. Interpretations belong to
  the derived semantic model class.
  """

  alias Src.Core.Logic.Lang.Symbol

  @type symbol_key :: Symbol.key()
  @type conflict :: term()
  @type t :: %__MODULE__{
    symbols: %{optional(symbol_key()) => Symbol.t()},
    metadata: map()
  }

  defstruct symbols: %{},
            metadata: %{}

  @doc """
  Adds a declaration without silently replacing an existing symbol.
  """
  @spec declare(t(), Symbol.t()) :: {:ok, t()} | {:error, conflict()}
  def declare(_signature, _symbol) do
    raise "Src.Core.Logic.Lang.Signature.declare/2 is not implemented"
  end

  @doc """
  Combines compatible signatures and reports everynaming or typing conflict.
  """
  @spec merge(t(), t()) :: {:ok, t()} | {:error, [conflict()]}
  def merge(_left, _right) do
    raise "Src.Core.Logic.Lang.Signature.merge/2 is not implemented"
  end
end
