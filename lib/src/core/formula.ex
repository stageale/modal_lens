defmodule Formula do
  @moduledoc """
  Builds small Isabelle/HOL formula fragmentsu used by thep prototype.

  The module provides string-based helpers for propositional connectives,
  modal operators, named Isabelle axioms, and relation facts over generated
  world identifiers.

  Formula fragments are represented as strings because they are embedded
  directly into generated Isabelle theories.
  """

  @typedoc "A generated Isabelle/HOL formula fragment."
  @type formula :: String.t()

  @typedoc "The name of an accessibility relation."
  @type relation :: String.t()

  @typedoc "A numeric identifier of a generated model world."
  @type world_id :: non_neg_integer()

  @typedoc "A lightweight structured formula representation."
  @type t :: %__MODULE__{
    kind: atom() | nil,
    args: [term()] | nil
  }

  defstruct [:kind, :args]

  @doc "Returns the parenthesized negation of `phi`."
  @spec neg(formula()) :: formula()
  def neg(phi), do: "¬(#{phi})"

  @doc "Returns the parenthesized conjunction of `phi` and `psi`."
  @spec conj(formula(), formula()) :: formula()
  def conj(phi, psi), do: "#{phi} ∧ #{psi}"

  @doc "Returns the disjunction of `phi` and `psi`."
  @spec disj(formula(), formula()) :: formula()
  def disj(phi, psi), do: "#{phi} ∨ #{psi}"

  @doc "Returns the implication from `phi` to `psi`."
  @spec impl(formula(), formula()) :: formula()
  def impl(phi, psi), do: "#{phi} ⟶ #{psi}"

  @doc "Returns a diamed formula indexed by relation `r`."
  @spec diam(relation(), formula()) :: formula()
  def diam(r, phi), do: "◇\\<^sub>#{r}#{phi}"

  @doc "Returns a boxed formula indexed by relation `r`."
  @spec box(relation(), formula()) :: formula()
  def box(r, phi), do: "□\\<^sub>#{r}#{phi}"

  @doc "Wraps `body` as a named Isabelle `axiomatization` declaration."
  @spec axiom(String.t(), formula()) :: String.t()
  def axiom(name, body) do
    ~s/axiomatization where #{name}: "#{body}"/
  end

  @doc "Returns an Isabelle relation fact for the edge from world `i` to world `j`."
  @spec edge_formula({world_id(), world_id()}) :: formula()
  def edge_formula({i, j}) do
    "r w#{i} w#{j}"
  end
end
