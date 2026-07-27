defmodule Src.Interface.Common.Run do
  @moduledoc """
  Describes one reproducible Axiom Refiner run.

  A run stores its parameters, generated artifacts, provenance,
  measurements, and current execution status. It does not execute
  the analysis pipeline itself.
  """

  @schema_version "1.0"

  @type status :: :planned | :running | :completed | :failed

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
  @spec put_artifact(t(), atom() | String.t(), term()) :: {:ok, t()} | {:error, term()}
  def put_artifact(%__MODULE__{} = run, name, value) do
    put_named_value(run, :artifacts, name, value)
  end

  @doc """
  Adds one provenance value to the run.
  """
  @spec put_provenance(t(), atom() | String.t(), term()) :: {:ok, t()} | {:error, term()}
  def put_provenance(%__MODULE__{} = run, name, value) do
    put_named_value(run, :provenance, name, value)
  end

  @doc """
  Adds one runtime or resource measurement to the run.
  """
  @spec put_metric(t(), atom() | String.t(), term()) :: {:ok, t()} | {:error, term()}
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
      "params" => json_safe(run.params),
      "artifacts" => json_safe(run.artifacts),
      "provenance" => json_safe(run.provenance),
      "metrics" => json_safe(run.metrics),
      "error" => json_safe(run.error)
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

  defp json_safe(nil), do: nil
  defp json_safe(value) when is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)

  defp json_safe(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> json_safe()
  end

  defp json_safe(value) when is_list(value) do
    Enum.map(value, &json_safe/1)
  end

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      {json_key(key), json_safe(nested_value)}
    end)
  end

  defp json_safe(value), do: value

  defp json_key(key) when is_binary(key), do: key
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: inspect(key)
end
