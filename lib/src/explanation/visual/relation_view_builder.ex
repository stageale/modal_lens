defmodule Src.Explanation.Visual.RelationViewBuilder do
  @moduledoc """
  Builds visualization relations from interpreted modal relations.

  The logical model remains unchanged. A relation view copies the original
  accessibility relation and dervies presentation from it.

  Structural properties are always computed on the original relation, never
  on an already simplified visualization.
  """

  alias Src.Core.Model.Modality

  alias Src.Explanation.Visual.GraphView.{RelationView, ViewEdge}

  @type world_index :: non_neg_integer()
  @type edge :: {world_index(), world_index()}

  @doc """
  Builds a visualization relation for one interpreted modality.

  By default, the modality kind is used as its filter key. This can be
  overridden when a future multimodal logic wants to expose a different grouping to the visualization frontend.

  No visualization reduction is performed here yet: every original edge is
  initially represented by one directed `ViewEdge`.
  """
  @spec build(Modality.t(), Enumerable.t(), keyword()) :: RelationView.t()
  def build(%Modality{} = modality, worlds, opts \\ []) do
    worlds =
      worlds
      |> Enum.to_list()
      |> Enum.uniq()
      |> Enum.sort()

    original_edges =
      modality.accessibility
      |> MapSet.new()

    validate_edges!(worlds, original_edges)

    properties = analyze(worlds, original_edges)

    view_edges =
      original_edges
      |> remove_reflexive_loops(properties)
      |> collapse_reciprocal_edges(properties)
      |> reduce_transitive_edges(properties, worlds)

    %RelationView{
      modality_id: Modality.id(modality),
      filter_key:
        opts
        |> Keyword.get(:filter_key, default_filter_key(modality))
        |> normalize_filter_key!(),
      symbol: modality.symbol,
      kind: modality.kind,
      agent: modality.agent,
      original_edges: original_edges,
      edges: view_edges,
      properties: properties
    }
  end

  defp analyze(worlds, edges) do
    %{
      reflexive: reflexive?(worlds, edges),
      symmetric: symmetric?(edges),
      transitive: transitive?(edges)
    }
  end

  defp reflexive?(worlds, edges) do
    Enum.all?(worlds, fn world ->
      MapSet.member?(edges, {world, world})
    end)
  end

  defp symmetric?(edges) do
    Enum.all?(edges, fn {source, target} ->
      MapSet.member?(edges, {target, source})
    end)
  end

  defp transitive?(edges) do
    adjacency =
      Enum.reduce(
        edges,
        %{},
        fn {source, target}, acc ->
          Map.update(acc, source, MapSet.new([target]), &MapSet.put(&1, target))
        end
      )

    Enum.all?(edges, fn {source, middle} ->
      adjacency
      |> Map.get(middle, MapSet.new())
      |> Enum.all?(fn target ->
        MapSet.member?(edges, {source, target})
      end)
    end)
  end

  defp remove_reflexive_loops(edges, %{reflexive: true}) do
    edges
    |> Enum.reject(fn {source, target} ->
      source == target
    end)
    |> MapSet.new()
  end

  defp remove_reflexive_loops(edges, %{reflexive: false}) do
    edges
  end

  defp collapse_reciprocal_edges(edges, %{symmetric: globally_symmetric?}) do
    edges
    |> Enum.sort()
    |> Enum.reduce(
      {MapSet.new(), []},
      fn {source, target} = edge, {seen, acc} ->
        reverse = {target, source}

        cond do
          MapSet.member?(seen, edge) ->
            {seen, acc}
          source == target ->
            {
              MapSet.put(seen, edge),
              [ %ViewEdge{source: source, target: target, direction: :forward} | acc ]
            }

          MapSet.member?(edges, reverse) ->
            {left, right} =
              if source <= target do
                {source, target}
              else
                {target, source}
              end

            direction =
              if globally_symmetric? do
                :undirected
              else
                :both
              end

            seen =
              seen
              |> MapSet.put(edge)
              |> MapSet.put(reverse)

            {
              seen,
              [ %ViewEdge{source: left, target: right, direction: direction} | acc ]
            }
        end
      end
    )
    |> elem(1)
    |> Enum.reverse()
  end

  defp reduce_transitive_edges(edges, %{transitive: false}, _worlds) do
    edges
  end

  defp reduce_transitive_edges(edges, %{transitive: true} = properties, worlds) do
    self_loops =
      Enum.filter(edges, fn %ViewEdge{source: source, target: target} ->
        source == target
      end)

    directed_edges =
      edges
      |> Enum.reject(fn
        %ViewEdge{source: source, target: target} ->
          source == target
      end)
      |> expand_view_edges()

    components =
      strongly_connected_components(worlds, directed_edges)

    component_of =
      component_index(components)

    quotient_edges =
      quotient_edges(directed_edges, component_of)

    reduced_quotient_edges =
      transitive_reduce_quotient(quotient_edges)

    internal_edges =
      components
      |> Enum.flat_map(fn component ->
        internal_component_generator(component, properties)
      end)

    connecting_edges =
      reduced_quotient_edges
      |> Enum.sort()
      |> Enum.map(fn {source_component, target_component} ->
        representative_edge!(directed_edges, component_of, source_component, target_component)
      end)
      |> Enum.map(fn {source, target} ->
        %ViewEdge{
          source: source,
          target: target,
          direction: :forward
        }
      end)

    (self_loops ++ internal_edges ++ connecting_edges)
    |> sort_view_edges()
  end

  defp expand_view_edges(edges) do
    Enum.reduce(
      edges,
      MapSet.new(),
      fn
        %ViewEdge{source: source, target: target, direction: :forward}, acc ->
          MapSet.put(acc, {source, target})
        %ViewEdge{source: source, target: target, direction: direction}, acc when direction in [:both, :undirected] ->
          acc
          |> MapSet.put({source, target})
          |> MapSet.put({target, source})
      end
    )
  end

  defp strongly_connected_components(worlds, directed_edges) do
    adjacency =
      adjacency_map(worlds, directed_edges)

    reachability =
      Map.new(worlds, fn world ->
        {
          world,
          reachable_from(world, adjacency)
        }
      end)

    build_components(Enum.sort(worlds), reachability, [])
  end

  defp build_components([], _reachability, components) do
    Enum.reverse(components)
  end

  defp build_components([world | remaining], reachability, components) do
    component =
      [world | remaining]
      |> Enum.filter(fn other ->
        MapSet.member?(Map.fetch!(reachability, world), other) and MapSet.member?(Map.fetch!(reachability, other), world)
      end)
      |> Enum.sort()

    component_set =
      MapSet.new(component)

    remaining =
      Enum.reject(remaining, fn other ->
        MapSet.member?(component_set, other)
      end)

    build_components(remaining, reachability, [component | components])
  end

  defp adjacency_map(worlds, edges) do
    initial =
      Map.new(worlds, fn world ->
        {world, MapSet.new()}
      end)

    Enum.reduce(
      edges,
      initial,
      fn {source, target}, adjacency ->
        Map.update!(adjacency, source, &MapSet.put(&1, target))
      end
    )
  end

  defp reachable_from(start, adjacency) do
    visit_reachable([start], adjacency, MapSet.new())
  end

  defp visit_reachable([], _adjacency, visited) do
    visited
  end

  defp visit_reachable([world | pending], adjacency, visited) do
    if MapSet.member?(visited, world) do
      visit_reachable(pending, adjacency, visited)
    else
      neighbours =
        adjacency
        |> Map.get(world, MapSet.new())
        |> MapSet.to_list()

      visit_reachable(neighbours ++ pending, adjacency, MapSet.put(visited, world))
    end
  end

  defp internal_component_generator(component, properties) do
    direction =
      if properties.symmetric do
        :undirected
      else
        :both
      end

    component
    |> Enum.sort()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [source, target] ->
      %ViewEdge{
        source: source,
        target: target,
        direction: direction
      }
    end)
  end

  defp component_index(components) do
    components
    |> Enum.with_index()
    |> Enum.reduce(
      %{},
      fn {component, index}, acc ->
        Enum.reduce(component, acc, fn world, acc ->
          Map.put(acc, world, index)
        end)
      end
    )
  end

  defp quotient_edges(directed_edges, component_of) do
    Enum.reduce(
      directed_edges,
      MapSet.new(),
      fn {source, target}, acc ->
        source_component =
          Map.fetch!(component_of, source)

        target_component =
          Map.fetch!(component_of, target)

        if source_component == target_component do
          acc
        else
          MapSet.put(
            acc,
            {source_component == target_component}
          )
        end
      end
    )
  end

  defp transitive_reduce_quotient(edges) do
    edges
    |> Enum.reject(fn {source, target} ->
      Enum.any?(edges, fn
        {^source, middle} when middle != target ->
          MapSet.member?(edges, {middle, target})
        _ -> false
      end)
    end)
    |> MapSet.new()
  end

  defp representative_edge!(directed_edges, component_of, source_component, target_component) do
    directed_edges
    |> Enum.filter(fn {source, target} -> Map.fetch!(component_of, source) == source_component
                                            and Map.fetch!(component_of, target) == target_component
    end)
    |> Enum.min()
  end

  defp sort_view_edges(edges) do
    Enum.sort_by(
      edges,
      fn %ViewEdge{source: source, target: target, direction: direction} ->
        {source, target, direction_order(direction)}
      end
    )
  end

  defp direction_order(:forward), do: 0
  defp direction_order(:both), do: 1
  defp direction_order(:undirected), do: 2

  defp default_filter_key(%Modality{kind: kind}) do
    Atom.to_string(kind)
  end

  defp normalize_filter_key!(key) when is_atom(key) do
    key |> Atom.to_string() |> normalize_filter_key!()
  end

  defp normalize_filter_key!(key) when is_binary(key) do
    case String.trim(key) do
      "" ->
        raise ArgumentError,
              "relation view filter key must not be empty"

      normalized ->
        normalized
    end
  end

  defp normalize_filter_key!(key) do
    raise ArgumentError,
          "relation view filter key must be a string or atom, got: " <>
            inspect(key)
  end

  defp validate_edges!(worlds, edges) do
    world_set = MapSet.new(worlds)

    Enum.each(
      edges,
      fn {source, target} = edge ->
        unless MapSet.member?(world_set, source) and MapSet.member?(world_set, target) do
          raise ArgumentError,
                "relation contains edge outside the model world set: " <>
                  inspect(edge)
        end
      end
    )
  end
end
