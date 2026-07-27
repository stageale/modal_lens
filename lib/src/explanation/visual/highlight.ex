defmodule Src.Explanation.Visual.Highlight do
  @moduledoc """
  Continuous attribution scores for worlds and existing edges of a model.

  Scores are normalized to the interval 0..1.
  """

  @type world :: non_neg_integer()
  @type edge :: {world(), world()}

  @type basis ::
        :semantic
        | :structural_metric
        | :feature
        | :pattern

  @type scope ::
        :model
        | :cluster

  @type score :: float()

  defstruct basis: nil,
            scope: :model,
            world_scores: %{},
            edge_scores: %{},
            tags: [],
            metadata: %{}


  @type t :: %__MODULE__{
        basis: basis() | nil,
        scope: scope(),
        world_scores: %{optional(world()) => score()},
        edge_scores: %{optional(edge()) => score()},
        metadata: map()
      }

  @spec empty() :: t()
  def empty do
    %__MODULE__{}
  end

  @doc """
  Builds a highlight from keyword attributes.

  Lists, MapSets and other enumerables are normalized to MapSets.
  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) when is_list(attrs) do
    %__MODULE__{
      basis: Keyword.get(attrs, :basis) |> validate_basis!(),
      scope: Keyword.get(attrs, :scope, :model) |> validate_scope!(),
      world_scores: Keyword.get(attrs, :world_scores, %{}) |> validate_world_scores!(),
      edge_scores: Keyword.get(attrs, :edge_scores, %{}) |> validate_edge_scores!(),
      tags: Keyword.get(attrs, :tags, []),
      metadata: Keyword.get(attrs, :metadata, %{}) |> validate_metadata!()
    }
  end

  @doc """
  Produces an empty highlight.

  This is useful while no deterministic cause analysis is available yet.
  """
  def empty?(%__MODULE__{} = heatmap) do
    map_size(heatmap.world_scores) == 0 and map_size(heatmap.edge_scores) == 0
  end

  @doc """
  Creates a highlight from any map or struct exposing the conventional
  highlight fields.

  This deliberately avoids a compile-time dependency on a specific
  explanation module.
  """
  @spec from_map(map(), keyword()) :: t()
  def from_map(source, opts \\ []) when is_map(source) do
    source_metadata =
      source
      |> Map.get(:metadata, %{})
      |> normalize_metadata()

    additional_metadata =
      opts
      |> Keyword.get(:metadata, %{})
      |> normalize_metadata()

    new(
      basis: Map.get(source, :basis),
      scope: Map.get(source, :scope, :model),
      world_scores: Map.get(source, :world_scores, %{}),
      edge_scores: Map.get(source, :edge_scores, %{}),
      tags: Map.get(source, :tags, []),
      metadata:
        source_metadata
        |> Map.merge(additional_metadata)
        |> Map.put_new(:source, Keyword.get(opts, :source, :unknown))
    )
  end

  @doc """
  Compatibility adapter for the former axiom-explanation pipeline.

  The argument is intentionally only required to be a map. This keeps the
  adapter usable without compiling the deprecated `AxiomExplanation` module.
  """
  @spec from_explanation(map()) :: t()
  def from_explanation(explanation) when is_map(explanation) do
    from_map(explanation,
      source: :axiom_explanation,
      metadata: %{
        axiom: Map.get(explanation, :axiom),
        status: Map.get(explanation, :status)
      }
    )
  end

  @spec world_score(t(), world(), score()) :: score()
  def world_score(%__MODULE__{} = heatmap, world, default \\ 0.0) do
    Map.get(heatmap.world_scores, world, default)
  end

  @spec edge_score(t(), edge(), score()) :: score()
  def edge_score(%__MODULE__{} = heatmap, edge, default \\ 0.0) do
    Map.get(heatmap.edge_scores, edge, default)
  end

  def put_world_score(%__MODULE__{} = heatmap, world, score) do
    validate_world!(world)
    score = validate_score!(score)

    %{heatmap |
      world_scores: Map.put(heatmap.world_scores, world, score)
    }
  end

  @spec put_edge_score(t(), edge(), number()) :: t()
  def put_edge_score(%__MODULE__{} = heatmap, {source, target} = edge, score) do
    validate_world!(source)
    validate_world!(target)
    score = validate_score!(score)

    %{heatmap |
      edge_scores: Map.put(heatmap.edge_scores, edge, score)
    }
  end

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}

  defp validate_basis!(nil), do: nil
  defp validate_basis!(basis) when basis in [:semantic, :structural_metric, :feature, :pattern], do: basis
  defp validate_basis!(basis) do
    raise ArgumentError,
          "invalid heatmap basis: #{inspect(basis)}"
  end

  defp validate_world_scores!(scores) when is_map(scores) do
    Map.new(scores, fn {world, score} ->
      validate_world!(world)
      {world, validate_score!(score)}
    end)
  end

  defp validate_world_scores!(scores) do
    raise ArgumentError,
          "world_scores must be a map, got: #{inspect(scores)}"
  end

  defp validate_edge_scores!(scores) when is_map(scores) do
    Map.new(scores, fn
      {{source, target} = edge, score} ->
        validate_world!(source)
        validate_world!(target)

        {edge, validate_score!(score)}
      {edge, _score} ->
        raise ArgumentError,
              "invalid edge identifier: #{inspect(edge)}"
    end)
  end

  defp validate_edge_scores!(scores) do
    raise ArgumentError,
          "edge_scores must be a map, got: #{inspect(scores)}"
  end

  defp validate_world!(world) when is_integer(world) and world >= 0, do: world
  defp validate_world!(world) do
    raise ArgumentError,
          "invalid world identifier: #{inspect(world)}"
  end

  defp validate_score!(score) when is_number(score) and score >= 0.0 and score <= 1.0, do: score / 1
  defp validate_score!(score) do
    raise ArgumentError,
          "heatmap score must be between 0.0 and 1.0, got: #{inspect(score)}"
  end

  defp validate_metadata!(metadata) when is_map(metadata), do: metadata
  defp validate_metadata!(metadata) do
    raise ArgumentError,
          "metadata must be a map, got: #{inspect(metadata)}"
  end

  defp validate_scope!(scope) when scope in [:model, :cluster], do: scope
  defp validate_scope!(scope) do
    raise ArgumentError,
          "invalid heatmap scope: #{inspect(scope)}"
  end
end
