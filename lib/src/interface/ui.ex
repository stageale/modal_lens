defmodule Src.Interface.Ui do
  @moduledoc """
  Runs and exports one interactive Axiom Refiner example.
  """

  alias Src.Interface.Common.Run
  alias Src.Interface.Ui.Launcher
  alias Src.Interface.Ui.Page
  alias Src.Interface.Ui.Session

  @doc "Calculates the selected configurations and writes the HTML view."
  @spec run(String.t(), String.t(), [map() | keyword()]) :: {:ok, Session.t(), String.t()} | {:error, term()} | {:error, term(), Run.t()}
  def run(theory_path, output_dir, option_sets \\ [%{}]) do
    page_path = Path.join(output_dir, "index.html")

    with {:ok, session} <- Launcher.run(theory_path, output_dir, option_sets),
         {:ok, page_path} <- Page.write(session, page_path) do
          {:ok, session, page_path}
         end
  end
end
