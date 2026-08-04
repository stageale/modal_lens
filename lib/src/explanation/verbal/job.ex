defmodule Src.Explanation.Verbal.Job do
  @moduledoc """
  Builds and writes Python verbalization job requests.
  """

  @request_schema "axiom-refiner/verbalization-request"
  @request_schema_version "1.0"
  @default_seed 42
  @default_max_new_tokens 768

  @enforce_keys [
    :backend,
    :model_id,
    :report_path,
    :output_directory
  ]

  defstruct [
    :backend,
    :model_id,
    :report_path,
    :output_directory,
    seed: @default_seed,
    max_new_tokens: @default_max_new_tokens,
    backend_options: %{}
  ]

  def new(backend, model_id, report_path, output_directory, opts \\ []) do
    seed = Keyword.get(opts, :seed, @default_seed)

    max_new_tokens = Keyword.get(opts, :max_new_tokens, @default_max_new_tokens)

    backend_options = Keyword.get(opts, :backend_options, %{})

    with  :ok <- validate_backend(backend),
          :ok <- validate_string(model_id, :model_id),
          :ok <- validate_string(report_path, :report_path),
          :ok <- validate_string(output_directory, :output_directory),
          :ok <- validate_non_negative_integer(seed, :seed),
          :ok <- validate_positive_integer(max_new_tokens, :max_new_tokens),
          :ok <- validate_backend_options(backend_options) do
      {:ok,
        %__MODULE__{
          backend: backend,
          model_id: model_id,
          report_path: report_path,
          output_directory: output_directory,
          seed: seed,
          max_new_tokens: max_new_tokens,
          backend_options: backend_options
        }
      }
    end
  end

  def to_map(%__MODULE__{} = job) do
    %{
      "schema" => @request_schema,
      "schema_version" => @request_schema_version,
      "backend" => job.backend,
      "model_id" => job.model_id,
      "report_path" => job.report_path,
      "output_directory" => job.output_directory,
      "seed" => job.seed,
      "max_new_tokens" => job.max_new_tokens,
      "backend_options" => job.backend_options
    }
  end

  def write(%__MODULE__{} = job, request_path) do
    request_path = Path.expand(request_path)

    request_directory = Path.dirname(request_path)

    with :ok <- File.mkdir_p(request_directory),
        {:ok, json} <- Jason.encode(to_map(job), pretty: true),
         :ok <- File.write(request_path, json <> "\n") do
           {:ok, request_path}
         end
  end

  def build_request_path(output_directory) do
    Path.join(output_directory, "verbalization_request.json")
  end

  defp validate_backend(backend) when backend in ["transformers", "ollama"] do
    :ok
  end

  defp validate_backend(_backend) do
    {:error, {:invalid_backend, ["transformers", "ollama"]}}
  end

  defp validate_string(value, field) when is_binary(value) and byte_size(value) > 0 do
    if String.trim(value) == "" do
      {:error, {:invalid_string, field}}
    else
      :ok
    end
  end

  defp validate_string(_value, field) do
    {:error, {:invalid_string, field}}
  end

  defp validate_non_negative_integer(value, _field) when is_integer(value) and value >= 0 do
    :ok
  end

  defp validate_non_negative_integer(_value, field) do
    {:error, {:invalid_non_negative_integer, field}}
  end

  defp validate_positive_integer(value, _field) when is_integer(value) and value > 0 do
    :ok
  end

  defp validate_positive_integer(_value, field) do
    {:error, {:invalid_positive_integer, field}}
  end

  defp validate_backend_options(options) when is_map(options) do
    :ok
  end

  defp validate_backend_options(_options) do
    {:error, :invalid_backend_options}
  end
end
