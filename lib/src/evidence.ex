defmodule Src.Evidence do
  @moduledoc """
  Defines the shared evidence contract used across ModalLens.

  Evidence records keep formal, deterministic structural, learned empirical,
  and operational observations explicitly separated. The module stores evidence
  only; it does not interpret payloads or perform reasoning itself.
  """

  @typedoc "The epistemic kind of an evidence record."
  @type kind ::
          :model
          | :proof
          | :structural
          | :learned
          | :operational

  @typedoc "The assurance level associated with an evidence kind."
  @type assurance ::
          :formal
          | :deterministic
          | :empirical
          | :operational

  @typedoc "The component or backend that produced the evidence."
  @type source :: atom() | String.t()

  @typedoc "A structured, evidence-kind-specific payload."
  @type payload :: map()

  @typedoc "Reproducibility and origin information for the evidence record."
  @type provenance :: map()

  @enforce_keys [
    :id,
    :kind,
    :source,
    :payload,
    :provenance,
    :assurance
  ]

  defstruct [
    :id,
    :kind,
    :source,
    :payload,
    :provenance,
    :assurance
  ]

  @typedoc "A single evidence record in the shared ModalLens evidence layer."
  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          source: source(),
          payload: payload(),
          provenance: provenance(),
          assurance: assurance()
        }

  @typedoc "An error returned when constructing an invalid evidence record."
  @type construction_error ::
          {:invalid_id, term()}
          | {:invalid_kind, term()}
          | {:invalid_source, term()}
          | {:invalid_payload, term()}
          | {:invalid_provenance, term()}

  @doc """
  Creates an evidence record and assigns the assurance implied by its kind.

  Model and proof evidence are formal, structural evidence is deterministic,
  learnede evidence is empirical, and operational evidence remains operational.
  """
  @spec new(String.t(), kind(), source(), payload()) ::
          {:ok, t()} | {:error, construction_error()}
  @spec new(String.t(), kind(), source(), payload(), provenance()) ::
          {:ok, t()} | {:error, construction_error()}
  def new(id, kind, source, payload, provenance \\ %{}) do
    with {:ok, id} <- normalize_id(id),
         :ok <- validate_kind(kind),
         {:ok, source} <- normalize_source(source),
         :ok <- validate_payload(payload),
         :ok <- validate_provenance(provenance) do
      {:ok,
       %__MODULE__{
         id: id,
         kind: kind,
         source: source,
         payload: payload,
         provenance: provenance,
         assurance: assurance_for(kind)
       }}
    end
  end

  @doc """
  Returns the assurance level fixed for an evidence kind.
  """
  @spec assurance_for(kind()) :: assurance()
  def assurance_for(kind) when kind in [:model, :proof], do: :formal
  def assurance_for(:structural), do: :deterministic
  def assurance_for(:learned), do: :empirical
  def assurance_for(:operational), do: :operational

  defp normalize_id(id) when is_binary(id) do
    case String.trim(id) do
      "" -> {:error, {:invalid_id, id}}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_id(id), do: {:error, {:invalid_id, id}}

  defp validate_kind(kind) when kind in [:model, :proof, :structural, :learned, :operational],
    do: :ok

  defp validate_kind(kind), do: {:error, {:invalid_kind, kind}}

  defp normalize_source(source) when is_atom(source), do: {:ok, source}

  defp normalize_source(source) when is_binary(source) do
    case String.trim(source) do
      "" -> {:error, {:invalid_source, source}}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_source(source), do: {:error, {:invalid_source, source}}

  defp validate_payload(payload) when is_map(payload), do: :ok
  defp validate_payload(payload), do: {:error, {:invalid_payload, payload}}

  defp validate_provenance(provenance) when is_map(provenance), do: :ok
  defp validate_provenance(provenance), do: {:error, {:invalid_provenance, provenance}}
end
