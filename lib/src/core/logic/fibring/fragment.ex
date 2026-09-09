defmodule Src.Core.Logic.Fibring.Fragment do
  @moduledoc """
  Describes one reusable component of a logic.

  A fragment contributes declarations, semantic clauses, and proof rules while
  making its requirements and provided capabilities explicit. It is data, not
  an execution callback, so a complete logic specification remains inspectable
  and serializable.
  """

  alias Src.Core.Logic.Lang.Operator
  alias Src.Core.Logic.Lang.Symbol
  alias Src.Core.Logic.ProofSystem
  alias Src.Core.Logic.Semantics.Contribution

  @type key :: atom() | {atom(), atom() | String.t()}
  @type capability :: term()
  @type type_contribution :: term()

  @type t :: %__MODULE__{
          key: key(),
          name: String.t() | nil,
          requires: [capability()],
          provides: [capability()],
          type_contributions: [type_contribution()],
          symbols: [Symbol.t()],
          operators: [Operator.t()],
          semantics: Contribution.t() | nil,
          proof_system: ProofSystem.t() | nil,
          metadata: map()
        }

  @enforce_keys [:key]
  defstruct key: nil,
            name: nil,
            requires: [],
            provides: [],
            type_contributions: [],
            symbols: [],
            operators: [],
            semantics: nil,
            proof_system: nil,
            metadata: %{}

  @doc """
  Checks the internal consistency of a fragment declaration.
  """
  @spec validate(t()) :: :ok | {:error, [term()]}
  def validate(_fragment) do
    raise "Src.Core.Logic.Fragment.validate/1 is not implemented"
  end

  @doc """
  Derives the capabilities actually provided by the declarations.

  Declared and derived capabilities will later be compared to prevent a
  fragment from claiming resources it does not define.
  """
  @spec derive_capabilities(t()) :: {:ok, [capability()]} | {:error, [term()]}
  def derive_capabilities(_fragment) do
    raise "Src.Core.Logic.Fragment.derive_capabilities/1 is not implemented"
  end
end
