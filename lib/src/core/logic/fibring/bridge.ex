defmodule Src.Core.Logic.Fibring.Bridge do
  @moduledoc """
  Declares an explicit fibring relation between component fragments.

  A bridge may identify or translate types and symbols, couple semantic
  structures, and weave proof principles. Incidental equality of names never
  creates a bridge automatically.
  """

  alias Src.Core.Logic.ProofSystem
  alias Src.Core.Logic.Semantics.Contribution

  @type key :: atom() | {atom(), atom() | String.t()}
  @type component_key :: term()
  @type capability :: term()
  @type mapping :: term()

  @type orientation ::
          :symmetric
          | {:directed, component_key(), component_key()}

  @type t :: %__MODULE__{
          key: key(),
          components: [component_key()],
          orientation: orientation(),
          requires: [capability()],
          provides: [capability()],
          type_mappings: [mapping()],
          symbol_mappings: [mapping()],
          operator_mappings: [mapping()],
          semantics: Contribution.t() | nil,
          proof_system: ProofSystem.t() | nil,
          metadata: map()
        }

  @enforce_keys [:key, :components]
  defstruct key: nil,
            components: [],
            orientation: :symmetric,
            requires: [],
            provides: [],
            type_mappings: [],
            symbol_mappings: [],
            operator_mappings: [],
            semantics: nil,
            proof_system: nil,
            metadata: %{}

  @doc """
  Checks component references, mappings, and local bridge consistency.
  """
  @spec validate(t()) :: :ok | {:error, [term()]}
  def validate(_bridge) do
    raise "Src.Core.Logic.Bridge.validate/1 is not implemented"
  end
end
