defmodule Src.Core.Logic.Type do
  @moduledoc """
  Represents a type expression together with the type theory that owns it.

  The wrapper deliberately does not prescribe simple, polymorphic, or
  dependent types. Its `expression` is interpreted and validated by the
  referenced `Src.Core.Logic.Type.Theory`.
  """

  @type theory_id :: atom() | module()
  @type expression :: term()

  @type t :: %__MODULE__{
          theory: theory_id(),
          expression: expression()
        }

  @enforce_keys [:theory, :expression]
  defstruct [:theory, :expression]

  @doc """
  Builds a type expression owned by `theory`.

  Validation against the selected type theory will be added with the first
  concrete type-theory implementation.
  """
  @spec new(theory_id(), expression()) :: {:ok, t()} | {:error, term()}
  def new(_theory, _expression) do
    raise "Src.Core.Logic.Type.new/2 is not implemented"
  end
end
