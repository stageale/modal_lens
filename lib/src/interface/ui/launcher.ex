defmodule Src.Interface.Ui.Launcher do
  @moduledoc """
  Calculates the UI variants of one Isabelle theory.
  """

  alias Src.Interface.Common.Run
  alias Src.Interface.Ui.Options
  alias Src.Interface.Ui.Service
  alias Src.Interface.Ui.Session


  @doc "Calculates the requested options sets for one theory."
  @spec run(String.t(), String.t(), [map() | keyword()]) :: {:ok, Session.t()} | {:error, term()} | {:error, term(), Run.t()}
  def run(theory_path, output_dir, option_sets \\ [%{}])

  def run(theory_path, output_dir, option_sets) when is_binary(theory_path) and is_binary(output_dir) and is_list(option_sets) do
    with {:ok, options} <- Options.new(),
         {:ok, session} <- Session.new(theory_path, options),
          :ok <- File.mkdir_p(output_dir) do
            execute_all(session, option_sets, output_dir)
          end
  end

  def run(_theory_path, _output_dir, _option_sets), do: {:error, :invalid_ui_run}

  defp execute_all(session, option_sets, output_dir) do
    option_sets
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, session}, fn {attrs, index}, {:ok, current_session} ->
      case execute(current_session, attrs, index, output_dir) do
        {:ok, updated_session} -> {:cont, {:ok, updated_session}}
        {:error, _reason} = error -> {:halt, error}
        {:error, _reason, _run} = error -> {:halt, error}
      end
    end)
  end

  defp execute(session, attrs, index, output_dir) do
    run_id = "ui-variant-#{index}"
    run_dir = Path.join(output_dir, run_id)

    with {:ok, options} <- Options.new(attrs) do
      Service.run(%{session | options: options}, run_id, run_dir)
    end
  end
end
