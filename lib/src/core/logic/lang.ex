defmodule Src.Core.Logic.Lang do
  @moduledoc """
  Represents the composed object language before semantic interpretation.

  Its well-formed expressions are not stored as a separate component. They
  are generated inductively from the selected type theory, signature, and
  operator declarations.
  """

  alias Src.Core.Logic.Lang.Operator
  alias Src.Core.Logic.Lang.Signature
  alias Src.Core.Logic.Type
  alias Src.Core.Logic.Type.Theory, as: TypeTheory

  @type operator_key :: Operator.key()

  @type t :: %__MODULE__{
          type_theory: TypeTheory.t(),
          signature: Signature.t(),
          operators: %{optional(operator_key()) => Operator.t()},
          metadata: map()
        }

  @enforce_keys [:type_theory, :signature]
  defstruct type_theory: nil,
            signature: nil,
            operators: %{},
            metadata: %{}

  @doc """
  Validates all declarations and their shared type-theoretic assumptions.
  """
  @spec validate(t()) :: :ok | {:error, [term()]}
  def validate(_language) do
    raise "Src.Core.Logic.Language.validate/1 is not implemented"
  end

  @doc """
  Infers the type of a language expression in a variable context.
  """
  @spec infer_type(t(), term(), TypeTheory.context()) ::
          {:ok, Type.t()} | {:error, term()}
  def infer_type(_language, _expression, _context) do
    raise "Src.Core.Logic.Language.infer_type/3 is not implemented"
  end
end
