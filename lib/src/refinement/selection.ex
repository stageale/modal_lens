defmodule Src.Refinement.Selection do
  @moduledoc """
  Selects one structural refinement candidate deterministically.

  Selection prefers higher cluster support, then lower outside support,
  then smaller graphlets. The candidate ID provides a stable final
  tie-breaker.

  Selection does not decide whether the candidate is applied
  """

  @typedoc "A JSON-decoded structural refinement candidate."
  @type candidate :: %{required(String.t()) => term()}

  @typedoc "An error encountered during candidate selection."
  @type selection_error ::
          :no_eligible_candidate
          | {:invalid_options, term()}
          | {:invalid_candidate, term()}

  @doc """
  Selects the best eligible refinement candidate.

  Candidates are ordered by:

    1. higher cluster support,
    2. lower outside support,
    3. smaller graphlet size,
    4. lexicographic candidate ID.
  """
  @spec select([candidate()]) :: {:ok, candidate()} | {:error, selection_error()}
  def select(candidates) when is_list(candidates) do
    invalid_candidate =
      Enum.reduce_while(candidates, nil, fn candidate, _acc ->
        if valid_candidate?(candidate) do
          {:cont, nil}
        else
          {:halt, {:invalid_candidate, candidate}}
        end
      end)

    case invalid_candidate do
      nil ->
        candidates
        |> Enum.sort_by(&ranking_key/1)
        |> case do
          [] -> {:error, :no_refinement_candidate}
          [selected | _remaining] -> {:ok, selected}
        end

      {:invalid_candidate, candidate} ->
        {:error, {:invalid_candidate, candidate}}
    end
  end

  def select(candidates) do
    {:error, {:invalid_options, candidates}}
  end

  @spec valid_candidate?(term()) :: boolean()
  defp valid_candidate?(%{
         "schema" => "modal-lens/refinement-candidate",
         "schema_version" => "1.0",
         "candidate_id" => candidate_id,
         "kind" => "exact_induced_graphlet_exclusion",
         "status" => "candidate",
         "origin" => %{
           "cluster_support" => cluster_support,
           "outside_support" => outside_support
         },
         "occurrence" => %{
           "size" => graphlet_size
         }
       }) do
    is_binary(candidate_id) and
      String.trim(candidate_id) != "" and
      is_number(cluster_support) and
      is_number(outside_support) and
      is_integer(graphlet_size) and
      graphlet_size > 0
  end

  defp valid_candidate?(_candidate), do: false

  @spec ranking_key(candidate()) :: tuple()
  defp ranking_key(candidate) do
    origin = candidate["origin"]

    {
      -origin["cluster_support"],
      origin["outside_support"],
      candidate["occurrence"]["size"],
      candidate["candidate_id"]
    }
  end
end
