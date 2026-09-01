defmodule Src.Core.Logic do
  @moduledoc """
  Represents a mathematical component logic as the five-tuple

     L = (T, Sigma, Omega, S, P)

  `language` packages the syntactic projection `(T, Sigma, Omega)`,
  `semantics` is the derived model class `S`, and `proof_system` is `P`.
  `Spec` remains the declarative construction recipe; this module represents
  the resulting mathematical object independently of its construction.
  """

  alias Src.Core.Logic.Lang
  alias Src.Core.Logic.Lang.Operator
  alias Src.Core.Logic.Lang.Signature
  alias Src.Core.Logic.ProofSystem
  alias Src.Core.Logic.Semantics.ModelClass
  alias Src.Core.Logic.Type.Theory, as: TypeTheory

  @type operator_map :: %{optional(Operator.key()) => Operator.t()}

  @type five_tuple :: {TypeTheory.t(), Signature.t(), operator_map(), ModelClass.t(), ProofSystem.t()}

  @type t :: %__MODULE__{
    name: String.t(),
    language: Lang.t(),
    semantics: ModelClass.t(),
    proof_system: ProofSystem.t(),
    metadata: map()
  }

  @enforce_keys [:name, :language, :semantics, :proof_system]
  defstruct name: nil,
            language: nil,
            semantics: nil,
            proof_system: nil,
            metadata: %{}

  @doc """
  Creates a component logic after all five parts have been supplied.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, [term()]}
  def new(_attributes) do
    raise "Src.Core.Logic.new/1 is not implemented"
  end

  @doc """
  Returns thee explicit mathematical five-tuple `(T, Sigma, Omega, S, P)`.
  """
  @spec as_tuple(t()) :: five_tuple()
  def as_tuple(%__MODULE__{
    language: %Lang{} = lang,
    semantics: semantics,
    proof_system: proof_sys
  }) do
    {
      lang.type_theory,
      lang.signature,
      lang.operators,
      semantics,
      proof_sys
    }
  end

  @doc """
  Validates the language, its model class, and its proof-theoretic interface as
  one coherent logic.
  """
  @spec validate(t()) :: :ok | {:error, [term()]}
  def validate(_logic) do
    raise "Src.Core.Logic.validate/1 is not implemented"
  end
end
