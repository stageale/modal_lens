defmodule Src.Core.Logic.ProofSystem do
  @moduledoc """
  Declares the proof-theoretic side of a component or fibred logic.

  ModalLens may initially leave this structure sparse and rely on generated
  Isabelle/HOL embeddings. Keepint it explicit allows later weaving of axioms,
  inference rules, and consequence relations in the sense of fibred logics.
  """

  @type judgement :: term()
  @type axiom_schema :: term()
  @type inference_rule :: term()
  @type property :: term()

  @type t :: %__MODULE__{
    judgements: [judgement()],
    axioms: [axiom_schema()],
    rules: [inference_rule()],
    claimed_properties: [property()],
    metadata: map()
  }

  defstruct judgements: [],
            axioms: [],
            rules: [],
            claimed_properties: [],
            metadata: %{}

  @doc """
  Weaves compatible proof-system contributions.
  """
  @spec merge(t(), t()) :: {:ok, t()} | {:error, [term()]}
  def merge(_left, _right) do
    raise "Src.Core.Logic.ProofSystem.merge/2 is not implemented"
  end
end
