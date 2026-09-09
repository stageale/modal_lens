defmodule Src.Core.Logic.Semantics.Contribution do
  @moduledoc """
  Declares the local semantic contribution of a fragment or bridge.

  Contributions remain declarative: they introduce carriers and parameters,
  assign semantic clauses to declarations, and constrain admissible models.
  The Composer later combines them into a global `ModelClass`.
  """

  @type carrier_declaration :: term()
  @type parameter_declaration :: term()
  @type clause_key :: term()
  @type semantic_clause :: term()
  @type constraint :: term()

  @type t :: %__MODULE__{
    carriers: [carrier_declaration()],
    parameters: [parameter_declaration()],
    clauses: %{optional(clause_key()) => semantic_clause()},
    constraints: [constraint()],
    metadata: map()
  }

  defstruct carriers: [],
            parameters: [],
            clauses: %{},
            constraints: [],
            metadata: %{}

  @doc """
  Combines compatible semantic contributions without solving open choices.

  Conflicting clauses or carrier declarations must be reported rather than overwritten.
  """
  @spec merge(t(), t()) :: {:ok, t()} | {:error, [term()]}
  def merge(_left, _right) do
    raise "Src.Core.Logic.Semantics.Contribution.merge/2 is not implemented"
  end
end
