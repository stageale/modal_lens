defmodule Src.Interface.Ui.Session do
  @moduledoc """
  Collects the calculated UI variants for one Isabelle theory.
  """

  alias Src.Execution.Run
  alias Src.Execution.Options

  @type variant :: %{
    options: Options.t(),
    run: Run.t(),
    result: map()
  }

  @type t :: %__MODULE__{
    theory_path: String.t(),
    variants: [variant()]
  }

  @enforce_keys :theory_path

  defstruct [:theory_path, variants: []]


  @doc "Creates a UI session for one Isabelle theory."
  @spec new(String.t()) :: {:ok, t()} | {:error, :invalid_theory_path}
  def new(theory_path) when is_binary(theory_path) do
    case String.trim(theory_path) do
      "" ->
        {:error, :invalid_theory_path}

      path ->
        {:ok, %__MODULE__{theory_path: Path.expand(path)}}
    end
  end

  def new(_theory_path), do: {:error, :invalid_theory_path}

  @doc "Stores one calculated result in the session."
  @spec put_variant(t(), Options.t(), Run.t(), map()) :: t()
  def put_variant(
    %__MODULE__{} = session,
    %Options{} = options,
    %Run{} = run,
    result
  ) when is_map(result) do
    variant = %{
      options: options,
      run: run,
      result: result
    }
    remaining_variants =
      session.variants
      |> Enum.reject(&(&1.options == options))

    %{session | variants: [variant | remaining_variants]}
  end
end
