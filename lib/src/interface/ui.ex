defmodule Src.Interface.Ui do
  @moduledoc """
  Runs and exports one interactive Axiom Refiner example.
  """

  alias Src.Execution.Pipeline
  alias Src.Execution.Run
  alias Src.Interface.Ui.Options
  alias Src.Interface.Ui.Page
  alias Src.Interface.Ui.Session

  @doc "Calculates the selected configurations and writes the HTML view."
  def run(theory_path, output_dir, option_sets \\ [%{}])

  def run(theory_path, output_dir, option_sets)
      when is_binary(theory_path) and is_binary(output_dir) and
             is_list(option_sets) do
    page_path = Path.join(output_dir, "index.html")

    with {:ok, session} <- Session.new(theory_path),
         :ok <- File.mkdir_p(output_dir),
         {:ok, completed_session} <-
           execute_all(session, option_sets, output_dir),
         {:ok, page_path} <- Page.write(completed_session, page_path) do
      {:ok, completed_session, page_path}
    end
  end

  def run(_theory_path, _output_dir, _option_sets) do
    {:error, :invalid_ui_run}
  end

  defp execute_all(session, option_sets, output_dir) do
    option_sets
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, session}, fn {option_attrs, index}, {:ok, current_session} ->
      case execute_variant(
        current_session,
        option_attrs,
        index,
        output_dir
      ) do
        {:ok, updated_session} ->
          {:cont, {:ok, updated_session}}

        {:error, _reason} = error ->
          {:halt, error}

        {:error, _reason, _run} = error ->
          {:halt, error}
      end
    end)
  end

  defp execute_variant(session, option_attrs, index, output_dir) do
    run_id = "ui-variant-#{index}"
    run_dir = Path.join(output_dir, run_id)

    with {:ok, options} <- Options.new(option_attrs),
        params = Options.to_run_params(options),
        {:ok, run} <- Run.new(run_id, run_dir, params),
        {:ok, completed_run, result} <- Pipeline.run_theory(run, session.theory_path) do

          {:ok,
           Session.put_variant(
             session,
             options,
             completed_run,
             result
           )}
        else
          {:error, reason, failed_run} ->
            {:error, reason, failed_run}

          {:error, reason} ->
            {:error, reason}
        end
  end
end
