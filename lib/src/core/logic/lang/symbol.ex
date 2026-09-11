defmodule Src.Core.Logic.Lang.Symbol do
  @moduledoc """
  Declares a non-logical resource of a language signature.

  Constants, functions, predicates, relations, propositions, and
  higher-order resources share the same typed representation. `kind` and
  `role` preserve their mathematical intention for validation, model generation, visualization, and explanation.
  """

  alias Src.Core.Logic.Type

  @type key :: atom() | {atom(), atom() | String.t()}

  @type kind ::
          :constant
          | :function
          | :predicate
          | :relation
          | :proposition
          | :higher_order
          | atom()

  @type dependence :: :rigid | :flexible | :unspecified
  @type role :: :object | :frame | :semantic | {:custom, atom()}

  @type t :: %__MODULE__{
          key: key(),
          name: String.t(),
          kind: kind(),
          type: Type.t(),
          dependence: dependence(),
          role: role(),
          metadata: map()
        }

  @enforce_keys [:key, :name, :kind, :type]
  defstruct key: nil,
            name: nil,
            kind: nil,
            type: nil,
            dependence: :unspecified,
            role: :object,
            metadata: %{}

  @doc """
  Creates and validates a typed symbol declaration.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(_attributes) do
    raise "Src.Core.Logic.Lang.Symbol.new/1 is not implemented"
  end
end
