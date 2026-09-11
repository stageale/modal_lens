defmodule Src.Core.Logic.Type.Theory do
  alias Src.Core.Logic.Type

  @type id :: atom()
  @type context :: term()
  @type substitution :: term()
  @type type_error :: term()

  @type t :: %__MODULE__{
          id: id(),
          provider: module(),
          options: map()
        }

  @enforce_keys [:id, :provider]
  defstruct id: nil,
            provider: nil,
            options: %{}

  @doc """
  Determines whether a type is well formed in a context.
  """
  @callback well_formed_type?(Type.t(), context(), map()) :: boolean()

  @doc """
  Infers the type of a structural term in a context.

  Logical operator applications will later by checked by `Lang`, using
  this judgement for their variables and structural subterms.
  """
  @callback infer(term(), context(), map()) :: {:ok, Type.t()} | {:error, type_error()}

  @doc """
  Performs capture-avoiding substitution according to the type theory.
  """
  @callback substitute(term(), substitution(), map()) :: {:ok, term()} | {:error, type_error()}

  @doc """
  Decides or normalizes type equivalence when the theory supports it.
  """
  @callback equivalent?(Type.t(), Type.t(), map()) :: boolean()

  @optional_callbacks equivalent?: 3

  @doc """
  Creates a reference to a type-theory provider.
  """
  @spec new(id(), module(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(_id, _provider, _options \\ []) do
    raise "Src.Core.Logic.Type.Theory.new/3 is not implemented"
  end

  @doc """
  Checks that the provider implements the declared type-theory contract.
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(_type_theory) do
    raise "Src.Core.Logic.Type.Theory.validate/1 is not implemented"
  end
end
