defmodule Src.Interface.Common.Service do
  @moduledoc """
  Executes one experiment as a reproducible run.

  The service connects the existing experiment pipeline with
  run state management and artifact persistence.
  """

  alias Src.Interface.Common.ArtifactStore
  alias Src.Interface.Common.Run
  alias Src.Interface.Experiment

  @type result :: {:ok, Run.t(), map()} | {:error, term(), Run.t()}

  @doc """
  Executes one Isabelle theory within the given run.
  """
  @spec run_theory(Run.t(), String.t()) :: result()
  def run_theory(%Run{} = run, theory_path) when is_binary(theory_path) do
    started_at = System.monotonic_time(:millisecond)

    experiment_opts =
      run.params
      |> Map.to_list()
      |> Keyword.put(:run_id, run.id)
      |> Keyword.put(:output_dir, run.output_dir)

    with {:ok, running_run} <- Run.start(run) do
      case Experiment.analyse_theory(theory_path, experiment_opts) do
        {:ok, experiment_result} -> finish_success(running_run, experiment_result, started_at)
        {:error, reason} -> finish_failure(running_run, reason, started_at)
      end
    else
      {:error, reason} -> {:error, reason, run}
    end
  end

  defp finish_success(%Run{} = run, experiment_result, started_at) do
    runtime_ms = System.monotonic_time(:millisecond) - started_at

    backend =
      experiment_result
      |> Map.get(:isabelle_run, %{})
      |> Map.get(:backend, Map.get(run.params, :backend, :local))

    with {:ok, run} <- register_artifacts(run, experiment_result),
         {:ok, run} <- Run.put_provenance(run, :backend, backend),
         {:ok, run} <- Run.put_metric(run, :runtime_ms, runtime_ms),
         {:ok, completed_run} <- Run.complete(run),
         {:ok, _manifest_path} <- ArtifactStore.persist(completed_run) do
      {:ok, completed_run, experiment_result}
    else
      {:error, reason} -> finish_failure(run, reason, started_at)
    end
  end

  defp finish_failure(%Run{} = run, reason, started_at) do
    runtime_ms = System.monotonic_time(:millisecond) - started_at

    with {:ok, run} <- Run.put_metric(run, :runtime_ms, runtime_ms),
         {:ok, failed_run} <- Run.fail(run, reason),
         {:ok, _manifest_path} <- ArtifactStore.persist(failed_run) do
      {:error, reason, failed_run}
    else
      {:error, persistence_reason} ->
        {:error, {:run_failure_not_persisted, reason, persistence_reason}, run}
    end
  end

  defp register_artifacts(%Run{} = run, experiment_result) do
    artifacts = [
      {
        :nitpick_output,
        Map.get(experiment_result, :nitpick_output_file)
      },
      {
        :graph_dot,
        Map.get(experiment_result, :graph_dot_file)
      },
      {
        :graph_image,
        Map.get(experiment_result, :graph_image_file)
      },
      {
        :blocking_axiom,
        Map.get(experiment_result, :blocking_axiom_file)
      }
    ]

    Enum.reduce_while(
      artifacts,
      {:ok, run},
      fn
        {_name, nil}, result ->
          {:cont, result}

        {name, path}, {:ok, current_run} ->
          case ArtifactStore.register(current_run, name, path) do
            {:ok, updated_run, _absolute_path} -> {:cont, {:ok, updated_run}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    )
  end
end
