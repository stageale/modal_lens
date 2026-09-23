defmodule Src.Execution.Options do
  @moduledoc """
  Defines and validates the parameters of one run.
  """

  alias Src.Explanation.Visual.Palette

  @model_logics [:sdl, :ddl, :ed_stit]
  @graph_formats [:svg, :tikz]
  @backends [:local, :hpc_connect]
  @feature_methods ["graphlet"]
  @default_palette Palette.default()
  @verbalization_backends ["transformers", "ollama"]
  @verbalization_modes [:grounded, :interpretive]
  @default_verbalization_max_new_tokens 768

  @type model_logic :: :sdl | :ddl | :ed_stit
  @type graph_format :: :svg | :tikz
  @type backend :: :local | :hpc_connect
  @type cardinality :: pos_integer()
  @type feature_method :: String.t()
  @type verbalization_mode :: :grounded | :interpretive

  @type t :: %__MODULE__{
          model_logic: model_logic(),
          backend: backend(),
          relation: String.t(),
          atoms: [String.t()],
          auto_atoms?: boolean(),
          cardinalities: [cardinality()],
          max_models: pos_integer(),
          max_parallel_renderers: pos_integer(),
          render_graph?: boolean(),
          graph_format: graph_format(),
          palette: Palette.palette(),
          include_atoms?: boolean(),
          include_designated_world?: boolean(),
          include_cardinality_feature?: boolean(),
          feature_method: feature_method(),
          graphlet_size: pos_integer(),
          verbalize?: boolean(),
          verbalization_backend: String.t(),
          verbalization_backend_options: map(),
          verbalization_model: String.t(),
          verbalization_mode: verbalization_mode(),
          verbalization_reasoning?: boolean(),
          verbalization_max_new_tokens: pos_integer()
        }

  defstruct model_logic: :sdl,
            backend: :local,
            relation: "R",
            atoms: [],
            auto_atoms?: true,
            cardinalities: [2],
            max_models: 10,
            max_parallel_renderers: 1,
            render_graph?: true,
            graph_format: :svg,
            palette: @default_palette,
            include_atoms?: true,
            include_designated_world?: true,
            include_cardinality_feature?: false,
            feature_method: "graphlet",
            graphlet_size: 3,
            verbalize?: true,
            verbalization_backend: "transformers",
            verbalization_backend_options: %{},
            verbalization_model: "HuggingFaceTB/SmolLM3-3B",
            verbalization_mode: :grounded,
            verbalization_reasoning?: false,
            verbalization_max_new_tokens: @default_verbalization_max_new_tokens

  @doc """
  Creates a validated option set.

  Enumerated options may be provided as atoms or strings.
  """
  @spec new() :: {:ok, t()} | {:error, term()}
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) do
    with {:ok, attrs} <- normalize_attrs(attrs),
         {:ok, attrs} <- normalize_values(attrs) do
      options = struct(__MODULE__, attrs)
      validate(options)
    end
  end

  @doc "Updates an existing option set."
  @spec update(t(), map() | keyword()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = options, attrs) do
    with {:ok, attrs} <- normalize_attrs(attrs) do
      options
      |> Map.from_struct()
      |> Map.merge(attrs)
      |> new()
    end
  end

  @doc "Returns the parameters stored for a user run."
  @spec to_run_params(t()) :: map()
  def to_run_params(%__MODULE__{} = options) do
    %{
      model_logic: options.model_logic,
      backend: options.backend,
      relation: options.relation,
      atoms: options.atoms,
      auto_atoms?: options.auto_atoms?,
      cardinalities: options.cardinalities,
      max_models: options.max_models,
      max_parallel_renderers: options.max_parallel_renderers,
      render_graph?: options.render_graph?,
      graph_format: options.graph_format,
      palette: options.palette,
      include_atoms?: options.include_atoms?,
      include_designated_world?: options.include_designated_world?,
      include_cardinality_feature?: options.include_cardinality_feature?,
      feature_method: options.feature_method,
      graphlet_size: options.graphlet_size,
      verbalize?: options.verbalize?,
      verbalization_backend: options.verbalization_backend,
      verbalization_backend_options: options.verbalization_backend_options,
      verbalization_model: options.verbalization_model,
      verbalization_mode: options.verbalization_mode,
      verbalization_reasoning?: options.verbalization_reasoning?,
      verbalization_max_new_tokens: options.verbalization_max_new_tokens
    }
  end

  defp validate(%__MODULE__{} = options) do
    cond do
      options.model_logic not in @model_logics ->
        {:error, {:invalid_model_logic, options.model_logic}}

      options.backend not in @backends ->
        {:error, {:invalid_backend, options.backend}}

      not is_binary(options.relation) or String.trim(options.relation) == "" ->
        {:error, :invalid_relation}

      not is_list(options.atoms) or not Enum.all?(options.atoms, &is_binary/1) ->
        {:error, :invalid_atoms}

      not valid_cardinalities?(options.cardinalities) ->
        {:error, {:invalid_cardinality, options.cardinalities}}

      not is_integer(options.max_models) or
          options.max_models <= 0 ->
        {:error, {:invalid_max_models, options.max_models}}

      options.graph_format not in @graph_formats ->
        {:error, {:invalid_graph_format, options.graph_format}}

      options.feature_method not in @feature_methods ->
        {:error, {:invalid_feature_method, options.feature_method}}

      options.graphlet_size != 3 ->
        {:error, {:invalid_graphlet_size, options.graphlet_size}}

      not Palette.valid?(options.palette) ->
        {:error, {:invalid_palette, options.palette}}

      options.verbalization_backend not in @verbalization_backends ->
        {:error, :invalid_verbalization_backend, options.verbalization_backend}

      not is_map(options.verbalization_backend_options) ->
        {:error, :invalid_verbalization_backend_options}

      not is_binary(options.verbalization_model) or String.trim(options.verbalization_model) == "" ->
        {:error, :invalid_verbalization_model}

      options.verbalization_mode not in @verbalization_modes ->
        {:error, {:invalid_verbalization_mode, options.verbalization_mode}}

      not is_integer(options.verbalization_max_new_tokens) or
          options.verbalization_max_new_tokens <= 0 ->
        {:error, {:invalid_verbalization_max_new_tokens, options.verbalization_max_new_tokens}}

      not is_integer(options.max_parallel_renderers) or options.max_parallel_renderers <= 0 ->
        {:error, {:invalid_max_parallel_renderers, options.max_parallel_renderers}}

      not boolean_options_valid?(options) ->
        {:error, :invalid_boolean_option}

      true ->
        {:ok, options}
    end
  end

  defp boolean_options_valid?(%__MODULE__{} = options) do
    Enum.all?(
      [
        options.auto_atoms?,
        options.render_graph?,
        options.include_atoms?,
        options.include_designated_world?,
        options.include_cardinality_feature?,
        options.verbalize?,
        options.verbalization_reasoning?
      ],
      &is_boolean/1
    )
  end

  defp normalize_values(attrs) do
    cardinality_value =
      Map.get(attrs, :cardinality, Map.get(attrs, :cardinalities, [2]))

    with {:ok, model_logic} <- normalize_model_logic(Map.get(attrs, :model_logic, :sdl)),
         {:ok, backend} <- normalize_backend(Map.get(attrs, :backend, :local)),
         {:ok, cardinalities} <- normalize_cardinalities(cardinality_value),
         {:ok, graph_format} <- normalize_graph_format(Map.get(attrs, :graph_format, :svg)),
         {:ok, feature_method} <-
           normalize_feature_method(Map.get(attrs, :feature_method, "graphlet")),
         {:ok, palette} <- normalize_palette(Map.get(attrs, :palette, @default_palette)),
         {:ok, verbalization_backend} <-
           normalize_verbalization_backend(Map.get(attrs, :verbalization_backend, "transformers")),
         {:ok, verbalization_mode} <-
           normalize_verbalization_mode(Map.get(attrs, :verbalization_mode, :grounded)),
         {:ok, verbalization_reasoning?} <-
           normalize_verbalization_reasoning(Map.get(attrs, :verbalization_reasoning?, false)) do
      {:ok,
       attrs
       |> Map.delete(:cardinality)
       |> Map.put(:model_logic, model_logic)
       |> Map.put(:backend, backend)
       |> Map.put(:cardinalities, cardinalities)
       |> Map.put(:graph_format, graph_format)
       |> Map.put(:feature_method, feature_method)
       |> Map.put(:palette, palette)
       |> Map.put(:verbalization_backend, verbalization_backend)
       |> Map.put(:verbalization_mode, verbalization_mode)
       |> Map.put(:verbalization_reasoning?, verbalization_reasoning?)}
    end
  end

  @spec normalize_verbalization_mode(term()) :: {:ok, verbalization_mode()} | {:error, term()}
  defp normalize_verbalization_mode(mode) when mode in @verbalization_modes do
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

  @spec normalize_verbalization_reasoning(term()) :: {:ok, boolean()} | {:error, term()}
  defp normalize_verbalization_reasoning(value) when is_boolean(value) do
    {:ok, value}
  end

  defp normalize_verbalization_reasoning(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "on" -> {:ok, true}
      "off" -> {:ok, false}
      _other -> {:error, {:invalid_verbalization_reasoning, value}}
    end
  end

  defp normalize_verbalization_reasoning(value) do
    {:error, {:invalid_verbalization_reasoning, value}}
  end

  defp normalize_cardinalities(value) when is_integer(value) and value > 0 do
    {:ok, [value]}
  end

  defp normalize_cardinalities(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      Regex.match?(~r/^\d+$/, value) ->
        cardinality = String.to_integer(value)

        if cardinality > 0 do
          {:ok, [cardinality]}
        else
          {:error, {:invalid_cardinality, value}}
        end

      match = Regex.run(~r/^(\d+)-(\d+)$/, value) ->
        [_, first, last] = match
        first = String.to_integer(first)
        last = String.to_integer(last)

        if first > 0 and first <= last do
          {:ok, Enum.to_list(first..last)}
        else
          {:error, {:invalid_cardinality, value}}
        end

      true ->
        {:error, {:invalid_cardinality, value}}
    end
  end

  defp normalize_cardinalities(value) when is_list(value) do
    if valid_cardinalities?(value) do
      {:ok, value}
    else
      {:error, {:invalid_cardinality, value}}
    end
  end

  defp normalize_cardinalities(value) do
    {:error, {:invalid_cardinality, value}}
  end

  defp valid_cardinalities?(cardinalities) when is_list(cardinalities) do
    cardinalities != [] and
      Enum.all?(cardinalities, &(is_integer(&1) and &1 > 0)) and
      cardinalities == Enum.sort(cardinalities) and
      cardinalities == Enum.uniq(cardinalities)
  end

  defp valid_cardinalities?(_cardinalities), do: false

  defp normalize_model_logic(value) when value in @model_logics do
    {:ok, value}
  end

  defp normalize_model_logic(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "sdl" -> {:ok, :sdl}
      "ddl" -> {:ok, :ddl}
      "ed_stit" -> {:ok, :ed_stit}
      "ed-stit" -> {:ok, :ed_stit}
      _other -> {:error, {:invalid_model_logic, value}}
    end
  end

  defp normalize_model_logic(value) do
    {:error, {:invalid_model_logic, value}}
  end

  defp normalize_backend(value) when value in @backends do
    {:ok, value}
  end

  defp normalize_backend(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "local" -> {:ok, :local}
      "hpc_connect" -> {:ok, :hpc_connect}
      "hpc-connect" -> {:ok, :hpc_connect}
      _other -> {:error, {:invalid_backend, value}}
    end
  end

  defp normalize_backend(value) do
    {:error, {:invalid_backend, value}}
  end

  defp normalize_graph_format(value) when value in @graph_formats do
    {:ok, value}
  end

  defp normalize_graph_format(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "svg" -> {:ok, :svg}
      "tikz" -> {:ok, :tikz}
      _other -> {:error, {:invalid_graph_format, value}}
    end
  end

  defp normalize_graph_format(value) do
    {:error, {:invalid_graph_format, value}}
  end

  defp normalize_feature_method(:graphlet), do: {:ok, "graphlet"}

  defp normalize_feature_method(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    if normalized in @feature_methods do
      {:ok, normalized}
    else
      {:error, {:invalid_feature_method, value}}
    end
  end

  defp normalize_feature_method(value) do
    {:error, {:invalid_feature_method, value}}
  end

  defp normalize_palette(value) when is_atom(value) do
    if Palette.valid?(value) do
      {:ok, value}
    else
      {:error, {:invalid_palette, value}}
    end
  end

  defp normalize_palette(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    case Enum.find(Palette.names(), &(Atom.to_string(&1) == normalized)) do
      nil -> {:error, {:invalid_palette, value}}
      palette -> {:ok, palette}
    end
  end

  defp normalize_palette(value) do
    {:error, {:invalid_palette, value}}
  end

  defp normalize_attrs(attrs) when is_map(attrs), do: {:ok, attrs}

  defp normalize_attrs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: {:ok, Map.new(attrs)},
      else: {:error, :invalid_options}
  end

  defp normalize_attrs(_attrs), do: {:error, :invalid_options}

  @spec normalize_verbalization_backend(term()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_verbalization_backend(backend) when backend in [:transformers, :ollama] do
    {:ok, Atom.to_string(backend)}
  end

  defp normalize_verbalization_backend(backend) when is_binary(backend) do
    normalized =
      backend
      |> String.trim()
      |> String.downcase()

    if normalized in @verbalization_backends do
      {:ok, normalized}
    else
      {:error, {:invalid_verbalization_backend, backend}}
    end
  end

  defp normalize_verbalization_backend(backend) do
    {:error, {:invalid_verbalization_backend, backend}}
  end
end
