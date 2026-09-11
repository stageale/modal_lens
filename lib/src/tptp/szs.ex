defmodule Src.TPTP.SZS do
  @moduledoc """
  Parses SZS statuses reported by automated theorem provers.

  The module distinguishes semantic results from operational outcomes
  such as timeouts, syntax errors, or abandoned proof searches.
  """

  @typedoc """
  SZS status relevant to the current ModalLens reasoning pipeline.
  """
  @type status ::
          :theorem
          | :counter_satisfiable
          | :satisfiable
          | :unsatisfiable
          | :contradictory_axioms
          | :unknown
          | :open
          | :timeout
          | :gave_up
          | :input_error
          | :syntax_error
          | :type_error

  @typedoc """
  Error encountered while reading an SZS result.
  """
  @type parse_error :: :status_not_found | {:unsupported_status, String.t()}

  @doc """
  Extracts the first SZS status from prover output.
  """
  @spec parse(String.t()) :: {:ok, status()} | {:error, parse_error()}
  def parse(output) when is_binary(output) do
    case Regex.run(~r/%\s*SZS\s+status\s+([A-Za-z]+)/, output, capture: :all_but_first) do
      [status] -> normalize(status)
      nil -> {:error, :status_not_found}
    end
  end

  @spec normalize(String.t()) :: {:ok, status()} | {:error, parse_error()}
  defp normalize(status) do
    case status do
      "Theorem" -> {:ok, :theorem}
      "CounterSatisfiable" -> {:ok, :counter_satisfiable}
      "Satisfiable" -> {:ok, :satisfiable}
      "Unsatisfiable" -> {:ok, :unsatisfiable}
      "ContradictoryAxioms" -> {:ok, :contradictory_axioms}
      "Unknown" -> {:ok, :unknown}
      "Open" -> {:ok, :open}
      "Timeout" -> {:ok, :timeout}
      "GaveUp" -> {:ok, :gave_up}
      "InputError" -> {:ok, :input_error}
      "SyntaxError" -> {:ok, :syntax_error}
      "TypeError" -> {:ok, :type_error}
      other -> {:error, {:unsupported_status, other}}
    end
  end

  @doc """
  Returns whether an SZS status establishes a semantic result.
  """
  @spec semantic_result?(status()) :: boolean()
  def semantic_result?(status) do
    status in [
      :theorem,
      :counter_satisfiable,
      :satisfiable,
      :unsatisfiable,
      :contradictory_axioms
    ]
  end
end
