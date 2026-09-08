defmodule Src.Execution.Options do
  @moduledoc """
  Defines and validates the parameters of one run.
  """

  alias Src.Explanation.Visual.Palette

  @model_logics [:sdl, :ddl]
  @graph_formats [:svg, :tikz]
  @backends [:local, :hpc_connect]
  @default_palette Palette.default()
  @verbalization_backends ["transformers", "ollama"]

  @type model_logic :: :sdl | :ddl
  @type graph_format :: :svg | :tikz
  @type backend :: :local | :hpc_connect

  @type t :: %__MODULE__{
          model_logic: model_logic(),
          backend: backend(),
          relation: String.t(),
          atoms: [String.t()],
          auto_atoms?: boolean(),
          max_models: pos_integer(),
          max_parallel_renderers: pos_integer(),
          render_graph?: boolean(),
          graph_format: graph_format(),
          palette: Palette.palette(),
          include_atoms?: boolean(),
          include_designated_world?: boolean(),
          verbalize?: boolean(),
          verbalization_backend: String.t(),
          verbalization_backend_options: map(),
          verbalization_model: String.t()
        }

  defstruct model_logic: :sdl,
            backend: :local,
            relation: "R",
            atoms: [],
            auto_atoms?: true,
            max_models: 10,
            max_parallel_renderers: 1,
            render_graph?: true,
            graph_format: :svg,
            palette: @default_palette,
            include_atoms?: true,
            include_designated_world?: true,
            verbalize?: true,
            verbalization_backend: "transformers",
            verbalization_backend_options: %{},
            verbalization_model: "HuggingFaceTB/SmolLM3-3B"

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
      max_models: options.max_models,
      max_parallel_renderers: options.max_parallel_renderers,
      render_graph?: options.render_graph?,
      graph_format: options.graph_format,
      palette: options.palette,
      include_atoms?: options.include_atoms?,
      include_designated_world?: options.include_designated_world?,
      verbalize?: options.verbalize?,
      verbalization_backend: options.verbalization_backend,
      verbalization_backend_options: options.verbalization_backend_options,
      verbalization_model: options.verbalization_model
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

      not is_integer(options.max_models) or
          options.max_models <= 0 ->
        {:error, {:invalid_max_models, options.max_models}}

      options.graph_format not in @graph_formats ->
        {:error, {:invalid_graph_format, options.graph_format}}

      not Palette.valid?(options.palette) ->
        {:error, {:invalid_palette, options.palette}}

      options.verbalization_backend not in @verbalization_backends ->
        {:error, :invalid_verbalization_backend, options.verbalization_backend}

      not is_map(options.verbalization_backend_options) ->
        {:error, :invalid_verbalization_backend_options}

      not is_binary(options.verbalization_model) or String.trim(options.verbalization_model) == "" ->
        {:error, :invalid_verbalization_model}

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
        options.verbalize?
      ],
      &is_boolean/1
    )
  end

  defp normalize_values(attrs) do
    with {:ok, model_logic} <- normalize_model_logic(Map.get(attrs, :model_logic, :sdl)),
         {:ok, backend} <- normalize_backend(Map.get(attrs, :model_logic, :local)),
         {:ok, graph_format} <- normalize_graph_format(Map.get(attrs, :graph_format, :svg)),
         {:ok, palette} <- normalize_palette(Map.get(attrs, :palette, @default_palette)),
         {:ok, verbalization_backend} <- normalize_verbalization_backend(Map.get(attrs, :verbalization_backend, "transformers")) do
      {:ok,
       attrs
       |> Map.put(:model_logic, model_logic)
       |> Map.put(:backend, backend)
       |> Map.put(:graph_format, graph_format)
       |> Map.put(:palette, palette)
       |> Map.put(:verbalization_backend, verbalization_backend)}
    end
  end

  defp normalize_model_logic(value) when value in @model_logics do
    {:ok, value}
  end

  defp normalize_model_logic(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "sdl" -> {:ok, :sdl}
      "ddl" -> {:ok, :ddl}
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
