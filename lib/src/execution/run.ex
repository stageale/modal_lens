defmodule Src.Execution.Run do
  @moduledoc """
  Describes one reproducible Axiom Refiner run.

  A run stores its parameters, generated artifacts, provenance,
  measurements, and current execution status. It does not execute
  the analysis pipeline itself.
  """

  alias Src.Serialization, as: Serial

  @schema_version "1.0"

  @type status :: :planned | :running | :completed | :failed
  @type name :: atom() | String.t()

  @type t :: %__MODULE__{
          id: String.t(),
          output_dir: String.t(),
          status: status(),
          params: map(),
          artifacts: map(),
          provenance: map(),
          metrics: map(),
          error: term() | nil
        }

  @enforce_keys [
    :id,
    :output_dir,
    :params
  ]

  defstruct [
    :id,
    :output_dir,
    status: :planned,
    params: %{},
    artifacts: %{},
    provenance: %{},
    metrics: %{},
    error: nil
  ]

  @doc """
  Creates a planned run with explicit identity, output directory,
  and immutable execution parameters.
  """
  @spec new(term(), term()) :: {:ok, t()} | {:error, term()}
  @spec new(term(), term(), term()) :: {:ok, t()} | {:error, term()}
  def new(id, output_dir, params \\ %{}) do
    with {:ok, id} <- normalize_non_empty_string(id, :id),
         {:ok, output_dir} <- normalize_non_empty_string(output_dir, :output_dir),
         :ok <- validate_map(params, :params) do
      {:ok,
       %__MODULE__{
         id: id,
         output_dir: Path.expand(output_dir),
         params: params
       }}
    end
  end

  @doc """
  Marks a planned run as running.
  """
  @spec start(t()) :: {:ok, t()} | {:error, term()}
  def start(%__MODULE__{status: :planned} = run) do
    {:ok, %{run | status: :running, error: nil}}
  end

  def start(%__MODULE__{} = run) do
    invalid_transition(run.status, :running)
  end

  @doc """
  Marks a running run as completed.
  """
  @spec complete(t()) :: {:ok, t()} | {:error, term()}
  def complete(%__MODULE__{status: :running} = run) do
    {:ok, %{run | status: :completed, error: nil}}
  end

  def complete(%__MODULE__{} = run) do
    invalid_transition(run.status, :completed)
  end

  @doc """
  Marks a planned or running run as failed and stores its reason.
  """
  @spec fail(t(), term()) :: {:ok, t()} | {:error, term()}
  def fail(%__MODULE__{status: status} = run, reason)
      when status in [:planned, :running] and not is_nil(reason) do
    {:ok, %{run | status: :failed, error: reason}}
  end

  def fail(%__MODULE__{}, nil) do
    {:error, :missing_failure_reason}
  end

  def fail(%__MODULE__{} = run, _reason) do
    invalid_transition(run.status, :failed)
  end

  @doc """
  Registers one generated artifact under a stable name.
  """
  @spec put_artifact(t(), name(), term()) :: {:ok, t()} | {:error, term()}
  def put_artifact(%__MODULE__{} = run, name, value) do
    put_named_value(run, :artifacts, name, value)
  end

  @doc """
  Returns the value registered for an artifact name.
  """
  @spec fetch_artifact(t(), name()) :: {:ok, term()} | {:error, term()}
  def fetch_artifact(%__MODULE__{} = run, name) do
    with {:ok, normalized_name} <- normalize_name(name) do
      case Map.fetch(run.artifacts, normalized_name) do
        {:ok, value} ->
          {:ok, value}

        :error ->
          {:error, {:unknown_artifact, normalized_name}}
      end
    end
  end

  @doc """
  Adds one provenance value to the run.
  """
  @spec put_provenance(t(), name(), term()) :: {:ok, t()} | {:error, term()}
  def put_provenance(%__MODULE__{} = run, name, value) do
    put_named_value(run, :provenance, name, value)
  end

  @doc """
  Adds one runtime or resource measurement to the run.
  """
  @spec put_metric(t(), name(), term()) :: {:ok, t()} | {:error, term()}
  def put_metric(%__MODULE__{} = run, name, value) do
    put_named_value(run, :metrics, name, value)
  end

  @doc """
  Converts the run into a JSON-compatible map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = run) do
    %{
      "schema_version" => @schema_version,
      "id" => run.id,
      "output_dir" => run.output_dir,
      "status" => Atom.to_string(run.status),
      "params" => Serial.safe(run.params),
      "artifacts" => Serial.safe(run.artifacts),
      "provenance" => Serial.safe(run.provenance),
      "metrics" => Serial.safe(run.metrics),
      "error" => Serial.safe(run.error)
    }
  end

  defp put_named_value(_run, _field, _name, nil) do
    {:error, :missing_value}
  end

  defp put_named_value(%__MODULE__{} = run, field, name, value) do
    with {:ok, normalized_name} <- normalize_name(name) do
      values =
        run
        |> Map.fetch!(field)
        |> Map.put(normalized_name, value)

      {:ok, Map.put(run, field, values)}
    end
  end

  defp normalize_name(name) when is_atom(name) do
    normalize_non_empty_string(Atom.to_string(name), :name)
  end

  defp normalize_name(name) when is_binary(name) do
    normalize_non_empty_string(name, :name)
  end

  defp normalize_name(_name) do
    {:error, :invalid_name}
  end

  defp normalize_non_empty_string(value, field) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, {:invalid_string, field}}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_non_empty_string(_value, field) do
    {:error, {:invalid_string, field}}
  end

  defp validate_map(value, _field) when is_map(value), do: :ok

  defp validate_map(_value, field), do: {:error, {:invalid_map, field}}

  defp invalid_transition(current_status, target_status) do
    {:error,
     {
       :invalid_status_transition,
       current_status,
       target_status
     }}
  end
end
