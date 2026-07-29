defmodule Src.Interface.Ui.Options do
  @moduledoc """
  Holds the user-selectable options for one countermodel analysis.
  """

  @model_logics [:sdl, :ddl]
  @graph_formats ["svg", "png"]
  @palettes [:cividis, :viridis, :plasma, :magma, :turbo]

  @type t :: %__MODULE__{
    model_logic: :sdl | :ddl,
    relation: String.t(),
    atoms: [String.t()],
    auto_atoms?: boolean(),
    render_graph?: boolean(),
    graph_format: String.t(),
    palette: atom(),
    include_atoms: boolean(),
    include_initial: boolean(),
    verbalize?: boolean(),
    verbalization_model: String.t()
  }

  defstruct [
    model_logic: :sdl,
    relation: "R",
    atoms: [],
    auto_atoms?: true,
    render_graph?: true,
    graph_format: :svg,
    palette: :turbo,
    include_atoms: true,
    include_initial: true,
    verbalize?: true,
    verbalization_model: "HuggingFaceTB/SmolLM3-3B",
  ]

  @doc "Creates a validated option set."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) do
    with {:ok, attrs} <- option_map(attrs) do
      attrs
      |> then(&struct(__MODULE__, &1))
      |> validate()
    end
  end

  @doc "Updates am existing option set."
  @spec update(t(), map() | keyword()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = options, attrs) do
    options
    |> Map.from_struct()
    |> Map.merge(attrs)
    |> new()
  end

  @doc "Returns the parameters stored for a user run."
  @spec to_run_params(t()) :: map()
  def to_run_params(%__MODULE__{} = options) do
    Map.from_struct(options)
  end

  defp validate(%__MODULE__{} = options) do
    cond do
      options.model_logic not in @model_logics -> {:error, {:invalid_model_logic, options.model_logic}}
      not is_binary(options.relation) or String.trim(options.relation) == "" -> {:error, :invalid_relation}
      not is_list(options.atoms) or not Enum.all?(options.atoms, &is_binary/1) -> {:error, :invalid_atoms}
      options.graph_format not in @graph_formats -> {:error, {:invalid_graph_format, options.graph_format}}
      options.palette not in @palettes -> {:error, {:invalid_palette, options.palette}}
      not is_binary(options.verbalization_model) or String.trim(options.verbalization_model) == "" -> {:error, :invalid_verbalization_model}
      not booleans?(options) -> {:error, :invalid_boolean_option}
      true -> {:ok, options}
    end
  end

  defp booleans?(%__MODULE__{auto_atoms?: a, render_graph?: b, include_atoms: c, include_initial: d, verbalize?: e}) do
    Enum.all?([a, b, c, d, e], &is_boolean/1)
  end

  defp option_map(attrs) when is_map(attrs), do: {:ok, attrs}

  defp option_map(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: {:ok, Map.new(attrs)},
      else: {:error, :invalid_options}
  end

  defp option_map(_attrs), do: {:error, :invalid_options}
end
