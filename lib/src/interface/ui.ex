defmodule Src.Interface.Ui do
  @moduledoc """
  Runs and exports one interactive ModalLens example.

  Ordinary UI runs execute one or more option variants. Completed refinement
  loops can be projected into the same UI without re-running their pipelines.
  """

  alias Src.Execution.Options
  alias Src.Execution.Pipeline
  alias Src.Execution.Run
  alias Src.Interface.Ui.Page
  alias Src.Interface.Ui.Session
  alias Src.Refinement.Loop

  @default_max_parallel_runs 1

  @type run_result ::
          {:ok, Session.t(), String.t()}
          | {:error, term()}
          | {:error, term(), Run.t()}

  @doc "Calculates the selected configurations and writes the HTML view."
  @spec run(String.t(), String.t()) :: run_result()
  @spec run(String.t(), String.t(), [map()]) :: run_result()
  @spec run(String.t(), String.t(), [map()], keyword()) :: run_result()
  def run(theory_path, output_dir, option_sets \\ [%{}], run_opts \\ [])

  def run(theory_path, output_dir, option_sets, run_opts)
      when is_binary(theory_path) and is_binary(output_dir) and
             is_list(option_sets) and is_list(run_opts) do
    page_path = Path.join(output_dir, "index.html")

    with {:ok, max_parallel_runs} <- max_parallel_runs(run_opts),
         {:ok, session} <- Session.new(theory_path),
         :ok <- File.mkdir_p(output_dir),
         {:ok, completed_session} <-
           execute_all(session, option_sets, output_dir, max_parallel_runs),
         {:ok, page_path} <- Page.write(completed_session, page_path) do
      {:ok, completed_session, page_path}
    end
  end

  def run(_theory_path, _output_dir, _option_sets, _run_opts) do
    {:error, :invalid_ui_run}
  end

  @doc "Writes a completed refinement loop into the existing HTML UI."
  @spec write_refinement(Loop.t(), String.t()) ::
          {:ok, Session.t(), String.t()} | {:error, term()}
  def write_refinement(%Loop{} = loop, output_dir) when is_binary(output_dir) do
    page_path = Path.join(output_dir, "index.html")

    with {:ok, options} <- options_from_run(loop.initial_run),
         {:ok, session} <- Session.new(loop.initial_theory_path),
         :ok <- File.mkdir_p(output_dir),
         completed_session = refinement_session(session, options, loop),
         {:ok, page_path} <- Page.write(completed_session, page_path) do
      {:ok, completed_session, page_path}
    end
  end

  def write_refinement(%Loop{}, _output_dir) do
    {:error, :invalid_ui_output_dir}
  end


  defp options_from_run(%Run{} = run) do
    option_keys =
      %Options{}
      |> Map.from_struct()
      |> Map.keys()

    run.params
    |> Map.take(option_keys)
    |> Options.new()
  end

  defp refinement_session(session, options, loop) do
    initial_variant = %{
      options: options,
      run: loop.initial_run,
      result: loop.initial_pipeline_result,
      stage: %{
        kind: :initial,
        label: "Initial analysis"
      },
      refinement: nil
    }

    refinement_variants =
      Enum.map(loop.iterations, fn iteration ->
        round_label =
          iteration.round
          |> Integer.to_string()
          |> String.pad_leading(3, "0")

        %{
          options: options,
          run: iteration.run,
          result: iteration.pipeline_result,
          stage: %{
            kind: :refinement,
            label: "Refinement round #{round_label}"
          },
          refinement: %{
            round: iteration.round,
            input_theory_path: iteration.input_theory_path,
            refined_theory_path: iteration.refined_theory.theory_path,
            candidate: iteration.selected_candidate,
            axiom: iteration.refined_theory.refinement_axiom
          }
        }
      end)

    variants = [initial_variant | refinement_variants]

    %{session | variants: Enum.reverse(variants)}
  end

  defp execute_all(session, option_sets, output_dir, max_parallel_runs) do
    option_sets
    |> Enum.with_index(1)
    |> Task.async_stream(
      fn {option_attrs, index} ->
        execute_variant(
          session.theory_path,
          option_attrs,
          index,
          output_dir
        )
      end,
      max_concurrency: max_parallel_runs,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, session}, fn
      {:ok, {:ok, options, completed_run, result}}, {:ok, current_session} ->
        updated_session =
          Session.put_variant(
            current_session,
            options,
            completed_run,
            result
          )

        {:cont, {:ok, updated_session}}

      {:ok, {:error, _reason} = error}, _acc ->
        {:halt, error}

      {:ok, {:error, _reason, _run} = error}, _acc ->
        {:halt, error}

      {:exit, reason}, _acc ->
        {:halt, {:error, {:variant_task_exit, reason}}}
    end)
  end

  defp execute_variant(theory_path, option_attrs, index, output_dir) do
    run_id = "ui-variant-#{index}"
    run_dir = Path.join(output_dir, run_id)

    with {:ok, options} <- Options.new(option_attrs),
         params = Options.to_run_params(options),
         {:ok, run} <- Run.new(run_id, run_dir, params),
         {:ok, completed_run, result} <- Pipeline.run_theory(run, theory_path) do
      {:ok, options, completed_run, result}
    else
      {:error, reason, failed_run} ->
        {:error, reason, failed_run}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp max_parallel_runs(run_opts) do
    case Keyword.get(
           run_opts,
           :max_parallel_runs,
           @default_max_parallel_runs
         ) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value ->
        {:error, {:invalid_max_parallel_runs, value}}
    end
  end
end
