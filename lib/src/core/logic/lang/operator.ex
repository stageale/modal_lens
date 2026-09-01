defmodule Src.Core.Logic.Lang.Operator.Argument do
  @moduledoc """
  Describes one argument position of an operator.

  `binds` lists the types of variables introduced in this argument. Thus an
  ordinary modal operator has an empty binding list, while a quantifier has
  one bound type in its formula argument.
  """

  alias Src.Core.Logic.Type

  @type t :: %__MODULE__{
    label: atom() | nil,
    binds: [Type.t()],
    type: Type.t()
  }

  @enforce_keys [:type]
  defstruct label: nil,
            binds: [],
            type: nil
end

defmodule Src.Core.Logic.Lang.Operator do
  @moduledoc """
  Declares a typed logical operator with an optional binding signature.

  Boolean connectives, quantifiers, modalities, lambda abstraction, and
  fixpoint operators use one common representation. Semantic meaning is
  referenced by `semantics_key` and supplied declaratively by a fragment.
  """

  alias Src.Core.Logic.Lang.Operator.Argument
  alias Src.Core.Logic.Type

  @type key :: atom() | {atom(), atom() | String.t()}
  @type side_condition :: term()

  @type t :: %__MODULE__{
    key: key(),
    name: String.t(),
    type_parameters: [term()],
    arguments: [Argument.t()],
    result: Type.t(),
    side_conditions: [side_condition()],
    semantics_key: term() | nil,
    metadata: map()
  }

  @enforce_keys [:key, :name, :arguments, :result]
  defstruct key: nil,
            name: nil,
            type_parameters: [],
            arguments: [],
            result: nil,
            side_conditions: [],
            semantics_key: nil,
            metadata: %{}

  @doc """
  Creates and validates an operator declaration.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(_attributes) do
    raise "Src.Core.Logic.Operator.new/1 is not implemented"
  end

  @doc """
  Checks the binding signature and result type in a type theory.
  """
  @spec validate(t(), Src.Core.Logic.Type.Theory.t()) :: :ok | {:error, term()}
  def validate(_operator, _type_theory) do
    raise "Src.Core.Logic.Lang.Operator.validate/2 is not implemented"
  end
end
