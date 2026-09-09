defmodule Src.Refinement.Loop do
  @moduledoc """
  Executes the outer structural refinement loop.

  The loop runs the ordinary ModalLens pipeline, obtains its selected
  refinement candidate, optionally applies that candidate, and start a new
  pipeline run on the refined theory.

  Model enumeration remains the inner loop of each pipeline run.
  """

  alias Src.Execution.Pipeline
  alias Src.Execution.Run
  alias Src.Refinement.Axiom
  alias Src.Refinement.Iteration
  alias Src.Refinement.Theory

  @typedoc "A structural refinement candidate"
  @type candidate :: Axiom.candidate()

  @typedoc """
  A function deciding whether a selected candidate is applied.

  The arguments are the prospective refinement round, the selected candidate,
  and the pipeline result from which it was selected.
  """
  @type decision_function :: (pos_integer(), candidate(), map() -> :apply | :stop)

  @typedoc "The decision mode used by the refinement loop."
  @type decision ::
          :automatic
          | decision_function()

  @typedoc "An option controlling the outer refinement loop."
  @type option ::
          {:max_rounds, non_neg_integer()}
          | {:decision, decision()}
          | {:theory, Theory.options()}

  @typedoc "Options controlling the outer refinement loop."
  @type options :: [option()]

  @typedoc "The reason why a completed refinement loop stopped."
  @type stop_reason ::
          :max_rounds
          | :no_refinement_candidate
          | :decision_stop

  @typedoc "An error encountered while executing the refinement loop."
  @type loop_error ::
          {:invalid_max_rounds, term()}
          | {:invalid_decision, term()}
          | {:initial_pipeline_failed, term()}
          | {:cannot_plan_refinement_run, pos_integer(), term()}
          | {:refinement_iteration_failed, pos_integer(), term()}

  @enforce_keys [
    :initial_theory_path,
    :initial_run,
    :initial_pipeline_result,
    :iterations,
    :final_theory_path,
    :final_run,
    :final_pipeline_result
  ]

  defstruct [
    :initial_theory_path,
    :initial_run,
    :initial_pipeline_result,
    :final_theory_path,
    :final_run,
    :final_pipeline_result,
    :stop_reason,
    iterations: []
  ]

  @typedoc "The accumulated result of the outer refinement loop."
  @type t :: %__MODULE__{
          initial_theory_path: String.t(),
          initial_run: Run.t(),
          initial_pipeline_result: map(),
          iterations: [Iteration.t()],
          final_theory_path: String.t(),
          final_run: Run.t(),
          final_pipeline_result: map(),
          stop_reason: stop_reason() | nil
        }

  @typedoc "The result of executing the outer refinement loop."
  @type result :: {:ok, t()} | {:error, loop_error(), Run.t()}

  @default_max_rounds 1
  @default_decision :automatic

  @doc """
  Runs the initial pipeline and up to `max_rounds` refinement iterations.

  With `decision: :automatic`, every selected candidate is applied
  automatically. A decision function can instead accept or reject each
  candidate, for example from an interactive CLI.
  """
  @spec run(Run.t(), String.t()) :: result()
  @spec run(Run.t(), String.t(), options()) :: result()
  def run(%Run{} = run, theory_path, opts \\ []) when is_binary(theory_path) and is_list(opts) do
    max_rounds = Keyword.get(opts, :max_rounds, @default_max_rounds)
    decision = Keyword.get(opts, :decision, @default_decision)
    theory_opts = Keyword.get(opts, :theory, [])

    cond do
      not is_integer(max_rounds) or max_rounds < 0 ->
        {:error, {:invalid_max_rounds, max_rounds}, run}

      decision != :automatic and not is_function(decision, 3) ->
        {:error, {:invalid_decision, decision}, run}

      true ->
        execute_initial_pipeline(
          run,
          theory_path,
          max_rounds,
          decision,
          theory_opts
        )
    end
  end

  @spec execute_initial_pipeline(
          Run.t(),
          String.t(),
          non_neg_integer(),
          decision(),
          Theory.options()
        ) :: result()
  defp execute_initial_pipeline(run, theory_path, max_rounds, decision, theory_opts) do
    case Pipeline.run_theory(run, theory_path) do
      {:ok, completed_run, pipeline_result} ->
        loop = %__MODULE__{
          initial_theory_path: Path.expand(theory_path),
          initial_run: completed_run,
          initial_pipeline_result: pipeline_result,
          iterations: [],
          final_theory_path: Path.expand(theory_path),
          final_run: completed_run,
          final_pipeline_result: pipeline_result,
          stop_reason: nil
        }

        continue(loop, 1, max_rounds, decision, theory_opts)

      {:error, reason, failed_run} ->
        {:error, {:initial_pipeline_failed, reason}, failed_run}
    end
  end

  @spec continue(t(), pos_integer(), non_neg_integer(), decision(), Theory.options()) :: result()
  defp continue(loop, round, max_rounds, _decision, _theory_opts) when round > max_rounds do
    {:ok, %{loop | stop_reason: :max_rounds}}
  end

  defp continue(loop, round, max_rounds, decision, theory_opts) do
    candidate = Map.get(loop.final_pipeline_result, :selected_refinement_candidate)

    case candidate do
      nil ->
        {:ok, %{loop | stop_reason: :no_refinement_candidate}}

      candidate ->
        case decide(decision, round, candidate, loop.final_pipeline_result) do
          :apply -> apply_candidate(loop, round, max_rounds, decision, theory_opts, candidate)
          :stop -> {:ok, %{loop | stop_reason: :decision_stop}}
          {:error, reason} -> {:error, reason, loop.final_run}
        end
    end
  end

  @spec decide(decision(), pos_integer(), candidate(), map()) ::
          :apply | :stop | {:error, loop_error()}
  defp decide(:automatic, _round, _candidate, _pipeline_result), do: :apply

  defp decide(decision, round, candidate, pipeline_result) when is_function(decision, 3) do
    case decision.(round, candidate, pipeline_result) do
      :apply -> :apply
      :stop -> :stop
      result -> {:error, {:invalid_decision, result}}
    end
  end

  @spec apply_candidate(
          t(),
          pos_integer(),
          non_neg_integer(),
          decision(),
          Theory.options(),
          candidate()
        ) :: result()
  defp apply_candidate(loop, round, max_rounds, decision, theory_opts, candidate) do
    round_label =
      round
      |> Integer.to_string()
      |> String.pad_leading(3, "0")

    run_id =
      "#{loop.initial_run.id}-refinement-#{round_label}"

    output_dir =
      Path.join(loop.initial_run.output_dir, "refinement/round-#{round_label}")

    case Run.new(run_id, output_dir, loop.initial_run.params) do
      {:ok, refinement_run} ->
        execute_iteration(
          loop,
          refinement_run,
          round,
          max_rounds,
          decision,
          theory_opts,
          candidate
        )

      {:error, reason} ->
        {:error, {:cannot_plan_refinement_run, round, reason}, loop.final_run}
    end
  end

  @spec execute_iteration(
          t(),
          Run.t(),
          pos_integer(),
          non_neg_integer(),
          decision(),
          Theory.options(),
          candidate()
        ) :: result()
  defp execute_iteration(
         loop,
         refinement_run,
         round,
         max_rounds,
         decision,
         theory_opts,
         candidate
       ) do
    iteration_opts = [
      round: round,
      theory: theory_opts
    ]

    case Iteration.run(refinement_run, loop.final_theory_path, candidate, iteration_opts) do
      {:ok, iteration} ->
        updated_loop = %{
          loop
          | iterations: loop.iterations ++ [iteration],
            final_theory_path: iteration.refined_theory.theory_path,
            final_run: iteration.run,
            final_pipeline_result: iteration.pipeline_result
        }

        continue(updated_loop, round + 1, max_rounds, decision, theory_opts)

      {:error, reason, failed_run} ->
        {:error, {:refinement_iteration_failed, round, reason}, failed_run}
    end
  end
end
