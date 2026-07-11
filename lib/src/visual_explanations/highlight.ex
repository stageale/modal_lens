defmodule Src.VisualExplanations.Highlight do
  @moduledoc """
  Describes structural elements that should be emphasized in a model
  visualization.

  A highlight is independent of the component that discovered the cause.
  It may later be produced from:

    * a deterministic DDL witness analysis,
    * a failed query,
    * a comparison between countermodels,
    * an LLM-assisted explanation,
    * or legacy axiom explanations.

  The renderer currently supports highlighted worlds, existing edges and
  missing edges.
  """

  defstruct responsible_edges: MapSet.new(),
            missing_edges: MapSet.new(),
            responsible_worlds: MapSet.new(),
            tags: [],
            metadata: %{}

  @type world :: non_neg_integer()
  @type edge :: {world(), world()}

  @type t :: %__MODULE__{
          responsible_edges: MapSet.t(edge()),
          missing_edges: MapSet.t(edge()),
          responsible_worlds: MapSet.t(world()),
          tags: list(),
          metadata: map()
        }

  @doc """
  Builds a highlight from keyword attributes.

  Lists, MapSets and other enumerables are normalized to MapSets.
  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) when is_list(attrs) do
    %__MODULE__{
      responsible_edges:
        attrs
        |> Keyword.get(:responsible_edges, [])
        |> normalize_set(),
      missing_edges:
        attrs
        |> Keyword.get(:missing_edges, [])
        |> normalize_set(),
      responsible_worlds:
        attrs
        |> Keyword.get(:responsible_worlds, [])
        |> normalize_set(),
      tags: Keyword.get(attrs, :tags, []),
      metadata: Keyword.get(attrs, :metadata, %{})
    }
  end

  @doc """
  Produces an empty highlight.

  This is useful while no deterministic cause analysis is available yet.
  """
  @spec empty() :: t()
  def empty do
    new()
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
      responsible_edges: Map.get(source, :responsible_edges, []),
      missing_edges: Map.get(source, :missing_edges, []),
      responsible_worlds: Map.get(source, :responsible_worlds, []),
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

  defp normalize_set(%MapSet{} = value), do: value
  defp normalize_set(nil), do: MapSet.new()
  defp normalize_set(value), do: MapSet.new(value)

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}
end