defmodule Src.VisualExplanations.Highlight do
  alias Src.VisualExplanations.AxiomExplanation

  defstruct [
    responsible_edges: MapSet.new(),
    missing_edges: MapSet.new(),
    responsible_worlds: MapSet.new(),
    tags: [],
    metadata: %{}
  ]

  def new(attrs \\ []) do
    %__MODULE__{
      responsible_edges:
        attrs
        |> Keyword.get(:responsible_edges, [])
        |> MapSet.new(),

      missing_edges:
        attrs
        |> Keyword.get(:missing_edges, [])
        |> MapSet.new(),

      responsible_worlds:
        attrs
        |> Keyword.get(:responsible_worlds, [])
        |> MapSet.new(),

      tags: Keyword.get(attrs, :tags, []),
      metadata: Keyword.get(attrs, :metadata, %{})
    }
  end

  def from_explanation(%AxiomExplanation{} = explanation) do
    new(
      responsible_edges: explanation.responsible_edges,
      missing_edges: explanation.missing_edges,
      responsible_worlds: explanation.responsible_worlds,
      tags: explanation.tags,
      metadata: %{
        source: :axiom_explanation,
        axiom: explanation.axiom,
        status: explanation.status
      }
    )
  end
end
