defmodule Src.Explanation.Verbal.Job do
  @moduledoc """
  Builds and writes Python verbalization job requests.
  """

  @request_schema "modal-lens/verbalization-request"
  @request_schema_version "1.0"
  @default_seed 42
  @default_max_new_tokens 768
  @default_verbalization_mode :grounded
  @default_reasoning false

  @enforce_keys [
    :backend,
    :model_id,
    :report_path,
    :output_directory
  ]

  @typedoc "Output style requested from the verbalizer."
  @type verbalization_mode :: :grounded | :interpretive

  @type t :: %__MODULE__{
          backend: String.t(),
          model_id: String.t(),
          report_path: String.t(),
          output_directory: String.t(),
          seed: non_neg_integer(),
          max_new_tokens: pos_integer(),
          backend_options: map(),
          verbalization_mode: verbalization_mode(),
          reasoning: boolean()
        }

  defstruct [
    :backend,
    :model_id,
    :report_path,
    :output_directory,
    seed: @default_seed,
    max_new_tokens: @default_max_new_tokens,
    backend_options: %{},
    verbalization_mode: @default_verbalization_mode,
    reasoning: @default_reasoning
  ]

  @doc "Creates and validates a verbalization job."
  @spec new(String.t(), String.t(), String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  @spec new(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def new(backend, model_id, report_path, output_directory, opts \\ []) do
    seed = Keyword.get(opts, :seed, @default_seed)
    max_new_tokens = Keyword.get(opts, :max_new_tokens, @default_max_new_tokens)
    backend_options = Keyword.get(opts, :backend_options, %{})

    reasoning = Keyword.get(opts, :reasoning, @default_reasoning)

    with {:ok, verbalization_mode} <-
           normalize_verbalization_mode(
             Keyword.get(opts, :verbalization_mode, @default_verbalization_mode)
           ),
         :ok <- validate_backend(backend),
         :ok <- validate_string(model_id, :model_id),
         :ok <- validate_string(report_path, :report_path),
         :ok <- validate_string(output_directory, :output_directory),
         :ok <- validate_non_negative_integer(seed, :seed),
         :ok <- validate_positive_integer(max_new_tokens, :max_new_tokens),
         :ok <- validate_backend_options(backend_options),
         :ok <- validate_reasoning(reasoning) do
      {:ok,
       %__MODULE__{
         backend: backend,
         model_id: model_id,
         report_path: report_path,
         output_directory: output_directory,
         seed: seed,
         max_new_tokens: max_new_tokens,
         backend_options: backend_options,
         verbalization_mode: verbalization_mode,
         reasoning: reasoning
       }}
    end
  end

  @doc "Converts a verbalization job into its serializable request map."
  @spec to_map(t()) :: map()
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
      "backend_options" => job.backend_options,
      "verbalization_mode" => Atom.to_string(job.verbalization_mode),
      "reasoning" => job.reasoning
    }
  end

  @doc "Writes the verbalization request as JSON to `request_path`."
  @spec write(t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def write(%__MODULE__{} = job, request_path) do
    request_path = Path.expand(request_path)

    request_directory = Path.dirname(request_path)

    with :ok <- File.mkdir_p(request_directory),
         {:ok, json} <- Jason.encode(to_map(job), pretty: true),
         :ok <- File.write(request_path, json <> "\n") do
      {:ok, request_path}
    end
  end

  @doc "Returns the default request-file path within `output_directory`."
  @spec build_request_path(String.t()) :: String.t()
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

  @spec normalize_verbalization_mode(term()) :: {:ok, verbalization_mode()} | {:error, term()}
  defp normalize_verbalization_mode(mode) when mode in [:grounded, :interpretive] do
    {:ok, mode}
  end

  defp normalize_verbalization_mode(mode) when is_binary(mode) do
    case mode |> String.trim() |> String.downcase() do
      "grounded" -> {:ok, :grounded}
      "interpretive" -> {:ok, :interpretive}
      _other -> {:error, {:invalid_verbalization_mode, mode}}
    end
  end

  defp normalize_verbalization_mode(mode) do
    {:error, {:invalid_verbalization_mode, mode}}
  end

  @spec validate_reasoning(term()) :: :ok | {:error, term()}
  defp validate_reasoning(reasoning) when is_boolean(reasoning) do
    :ok
  end

  defp validate_reasoning(reasoning) do
    {:error, {:invalid_verbalization_reasoning, reasoning}}
  end
end
