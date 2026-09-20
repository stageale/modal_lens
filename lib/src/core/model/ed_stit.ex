defmodule Src.Core.Model.EDSTIT do
  @moduledoc """
  Finite pointed model for Epistemic Deontic STIT.

  The model represents the atemporal ED-STIТ semantics used by ModalLens.
  It combines:

    * settledness,
    * agent-indexed STIT choice,
    * agent-indexed deontic ought-to-do,
    * agent-indexed belief.

  Modalities are represented explicitly by `Src.Core.Model.Modality`.
  Their current finite interpretations use accessibility pairs between
  worlds, while their semantic identity is kept separate from that
  representation.

  `actual_world` designates the world at which formulas are evaluated.

  Agents are stored explicitly rather than inferred from the modalities.
  This preserves the agent domain of the finite model even when a concrete
  modality has no accessibility pair for a particular agent.
  """

  alias Src.Core.Model.Modality
  alias Src.Core.ParseWarning

  @typedoc "A zero-based index identifying a world."
  @type world_index :: non_neg_integer()

  @typedoc "The kind of finite structure reported by Nitpick."
  @type result_kind :: :model | :countermodel

  @typedoc "A proposition valuation ordered by world index."
  @type valuation :: [boolean()]

  @typedoc "Identifier of an agent in the finite model."
  @type agent :: String.t()

  @typedoc "A finite pointed Epistemic Deontic STIT model."
  @type t :: %__MODULE__{
          source: String.t() | nil,
          kind: result_kind() | nil,
          cardinality: non_neg_integer(),
          actual_world: world_index(),
          agents: [agent()],
          modalities: [Modality.t()],
          valuations: %{optional(String.t()) => valuation()},
          warnings: [ParseWarning.t()],
          raw_text: String.t()
        }

  @enforce_keys [:cardinality]

  defstruct [
    :source,
    :kind,
    :cardinality,
    actual_world: 0,
    agents: [],
    modalities: [],
    valuations: %{},
    warnings: [],
    raw_text: ""
  ]

  @doc """
  Returns all modalities of a given semantic kind.
  """
  @spec modalities_by_kind(t(), Modality.kind()) :: [Modality.t()]
  def modalities_by_kind(%__MODULE__{modalities: modalities}, kind) do
    modalities
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.sort_by(&Modality.sort_key/1)
  end

  @doc """
  Returns the modality of `kind` associated with `agent`.

  Returns `nil` when no such modality occurs in the finite model.
  """
  @spec modality_for_agent(t(), Modality.kind(), agent()) ::
          Modality.t() | nil
  def modality_for_agent(
        %__MODULE__{modalities: modalities},
        kind,
        agent
      )
      when kind in [:stit, :ought, :belief] do
    Enum.find(
      modalities,
      fn modality ->
        modality.kind == kind and
          modality.agent == agent
      end
    )
  end

  @doc """
  Returns the global settledness modality, if present.
  """
  @spec settledness_modality(t()) :: Modality.t() | nil
  def settledness_modality(%__MODULE__{modalities: modalities}) do
    Enum.find(
      modalities,
      &(&1.kind == :settledness)
    )
  end
end
