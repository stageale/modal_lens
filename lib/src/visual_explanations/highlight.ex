defmodule Src.VisualExplanations.Highlight do
  alias Src.VisualExplanations.AxiomExplanation

  def new(attrs \\ []) do
    # TODO: construct a highlight object/map from given attributes
  end

  def from_explanation(%AxiomExplanation{} = explanation) do
    # TODO: convert an axiom explanation into rendereable highlight information
  end

  def empty do
    # TODO: return an empty highlight
  end

  def merge(highlight_a, highlight_b) do
    # TODO: merge two highlights into one
  end

  def responsible_edge?(highlight, edge) do
    # TODO: check whether a world should be highlighted
  end

  def edge_role(highlight, edge) do
    # TODO: return the role of an edge, e.g. :responsible, :missing, or :normal
  end

  def world_role(highlight, world) do
    # TODO: return the role of a world, e.g. :responsible or :normal
  end

  def edge_attrs(highlight, edge) do
    # TODO: return abstract render attributes for an edge
  end

  def world_attrs(highlight, world) do
    # TODO: return abstract render attributes for a world
  end

  def legend(highlight) do
    # TODO: return legend entries for the current highlight
  end

  def has_highlights?(highlight) do
    # TODO: check whether the highlight contains any marked worlds or edges
  end
end
