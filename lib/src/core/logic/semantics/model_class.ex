defmodule Src.Core.Logic.Semantics.ModelClass do
  @moduledoc """
  Represents the global semantic design derived by composition.

  A model class is the family of structures satisfying the assembled carrier
  declarations, interpretations, semantic clauses, and constraints. Remaining
  semantic parameters are explicit and prevent a strict compilation result.
  """

  alias Src.Core.Logic.Lang

  @type t :: %__MODULE__{
    language: Lang.t(),
    carriers: [term()],
    parameters: [term()],
    interpretations: %{optional(term()) => term()},
    clauses: %{optional(term()) => term()},
    constraints: [term()],
    unresolved_parameters: [term()],
    metadata: map()
  }

  @enforce_keys [:language]
  defstruct language: nil,
            carriers: [],
            parameters: [],
            interpretations: %{},
            clauses: %{},
            constraints: [],
            unresolved_parameters: [],
            metadata: %{}

  @doc """
  Checks the structural completeness of the derived model class.

  This is not a general consistency decision procedure. Logical consistency
  and faithfulness are emitted as proof obligations for external backends.
  """
  @spec validate(t()) :: :ok | {:error, [term()]}
  def validate(_model_class) do
    raise "Src.Core.Logic.Semantics.ModelClass.validate/1 is not implemented"
  end
end
