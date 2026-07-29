defmodule Src.Interface.Ui.Session do
  @moduledoc """
  Holds the current UI selection and its calculated results.
  """

  alias Src.Interface.Common.Run
  alias Src.Interface.Ui.Options

  @type t :: %__MODULE__{
    theory_path: String.t(),
    options: Options.t(),
    variants: [map()]
  }

  @enforce_keys [:theory_path, :options]

  defstruct [:theory_path, :options, variants: []]


  @doc "Creates a UI session for one Isabelle theory."
  @spec new(String.t(), Options.t()) :: {:ok, t()} | {:error, term()}
  def new(theory_path, %Options{} = options) when is_binary(theory_path) do
    case String.trim(theory_path) do
      "" -> {:error, :invalid_theory_path}
      path -> {:ok, %__MODULE__{
        theory_path: Path.expand(path),
        options: options
      }}
    end
  end

  def new(_theory_path, _options), do: {:error, :invalid_session}

  @doc "Changes the currently selected UI options."
  @spec select(t(), map() | keyword()) :: {:ok, t()} | {:error, term()}
  def select(%__MODULE__{} = session, attrs) do
    with {:ok, options} <- Options.update(session.options, attrs) do
      {:ok, %{session | options: options}}
    end
  end

  @doc "Stores one calculated result in the session."
  @spec put_variant(t(), Options.t(), Run.t(), map()) :: t()
  def put_variant(%__MODULE__{} = session, %Options{} = options, %Run{} = run, result) when is_map(result) do
    variant = %{
      options: options,
      run: run,
      result: result
    }
    variants =
      session.variants
      |> Enum.reject(&(&1.options == options))
      |> then(&[variant | &1])

    %{session | variants: variants}
  end

  @doc "Returns the result matching the current selection."
  @spec current_variant(t()) :: {:ok, map()} | :error
  def current_variant(%__MODULE__{} = session) do
    case Enum.find(session.variants, &(&1.options == session.options)) do
      nil -> :error
      variant -> {:ok, variant}
    end
  end
end
