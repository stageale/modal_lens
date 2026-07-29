defmodule Src.Interface.Ui.Service do
  @moduledoc """
  Executes the current UI configuration as one reproducible run.
  """

  alias Src.Interface.Common.Run
  alias Src.Interface.Common.Service, as: CommonService
  alias Src.Interface.Ui.Options
  alias Src.Interface.Ui.Session

  @doc "Executes the current selection of a UI session."
  def run(%Session{} = session, run_id, output_dir) do
    params = Options.to_run_params(session.options)

    with {:ok, run} <- Run.new(run_id, output_dir, params) do
      execute(session, run)
    end
  end

  defp execute(%Session{} = session, %Run{} = run) do
    case CommonService.run_theory(run, session.theory_path) do
      {:ok, completed_run, result} ->
        updated_session =
          Session.put_variant(session, session.options, completed_run, result)

        {:ok, updated_session}

      {:error, reason, failed_run} -> {:error, reason, failed_run}
    end
  end
end
