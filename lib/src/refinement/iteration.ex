defmodule Src.Refinement.Iteration do
  @moduledoc """
  Executes one structural refinement iteration.

  An iteration receives one previously selected refinement candidate,
  generates an Isabelle theory containing its refinement axiom, and executes
  the complete analysis pipeline on that refined theory.

  Candidate selection, interactive confirmation, and repeated refinement rounds
  are deliberately handled outside this module.
  """

  alias Src.Execution.ArtifactStore
  alias Src.Execution.Pipeline
  alias Src.Execution.Run
  alias Src.Refinement.Axiom
  alias Src.Refinement.Theory

  @typedoc "A structural refinement candidate accepted by the axiom renderer."
  @type candidate :: Axiom.candidate()

  @typedoc "An option controlling one refinement iteration."
  @type option :: {:round, pos_integer()}
                | {:theory, Theory.options()}

  @typedoc "Options controlling one refinement iteration."
  @type options :: [option()]

  @typedoc "An error encountered during one refinement iteration."
  @type iteration_error :: {:refinement_theory_failed, term()}
                        | {:refinement_theory_registration_failed, term()}
                        | {:refined_pipeline_failed, term()}

  @enforce_keys [
    :round,
    :input_theory_path,
    :selected_candidate,
    :refined_theory,
    :run,
    :pipeline_result
  ]

  defstruct [
    :round,
    :input_theory_path,
    :selected_candidate,
    :refined_theory,
    :run,
    :pipeline_result
  ]

  @typedoc "The completed result of one structural refinement iteration."
  @type t :: %__MODULE__{
    round: pos_integer(),
    input_theory_path: String.t(),
    selected_candidate: candidate(),
    refined_theory: Theory.t(),
    run: Run.t(),
    pipeline_result: map()
  }

  @typedoc "The result of attempting one refinement iteration."
  @type result :: {:ok, t()} | {:error, iteration_error(), Run.t()}

  @default_round 1

  @doc """
  Applies `candidate` to `input_theory_path` and runs the complete pipeline.

  The supplied run must be in its planned state. Its output directory is used
  for both the generated refinement theory and all subsequent pipeline
  artifacts.

  The candidate is applied without imposing support thresholds. Candidate
  ranking and user confirmation are responsibilities of the caller.
  """
  @spec run(Run.t(), String.t(), candidate()) :: result()
  @spec run(Run.t(), String.t(), candidate(), options()) :: result()
  def run(%Run{} = run, input_theory_path, candidate, opts \\ []) when is_binary(input_theory_path) and is_map(candidate) and is_list(opts) do
    round = Keyword.get(opts, :round, @default_round)
    theory_opts =
      opts
      |> Keyword.get(:theory, [])
      |> Keyword.put_new(:refinement_theory_dir, Path.join(run.output_dir, "refinement_theory"))
    case Theory.write(
      input_theory_path,
      candidate,
      theory_opts
    ) do
      {:ok, refined_theory} ->
        execute_refined_pipeline(
          run,
          input_theory_path,
          candidate,
          round,
          refined_theory
        )
      {:error, reason} -> {:error, {:refinement_theory_failed, reason}, run}
    end
  end

  @spec execute_refined_pipeline(Run.t(), String.t(), candidate(), pos_integer(), Theory.t()) :: result()
  defp execute_refined_pipeline(run, input_theory_path, candidate, round, refined_theory) do
    case ArtifactStore.register(run, :refinement_theory, refined_theory.theory_path) do
      {:ok, register_run, _absolute_path} ->
        case Pipeline.run_theory(
          register_run,
          refined_theory.theory_path
        ) do
          {:ok, completed_run, pipeline_result} ->
            {:ok,
              %__MODULE__{
                round: round,
                input_theory_path: Path.expand(input_theory_path),
                selected_candidate: candidate,
                refined_theory: refined_theory,
                run: completed_run,
                pipeline_result: pipeline_result
              }
            }
          {:error, reason, failed_run} -> {:error, {:refined_pipeline_failed, reason}, failed_run}
        end
      {:error, reason} ->
        {:error,
          {:refinement_theory_registration_failed, reason},
          run
        }
    end
  end
end
