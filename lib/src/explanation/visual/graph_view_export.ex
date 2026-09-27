defmodule Src.Explanation.Visual.GraphViewExport do
  @moduledoc """
  Writes the precomputed ED-STIT graph views as DOT, SVG, and TikZ files.
  """

  alias Src.Core.Model.EDSTIT, as: EDSTITModel
  alias Src.Explanation.Visual.GraphViewCatalog
  alias Src.Explanation.Visual.Render

  @doc """
  Exports every filter combination, including the empty selection.

  Returns `filter_keys`, `default_view`, and a map of view IDs to their
  selected modalities and artifact paths.

  `existing_full:` may contain the paths of an already rendered full view:

      %{
        graph_dot_file: dot_path,
        graph_svg_file: svg_path,
        graph_tikz_file: tikz_path
      }
  """
  @spec write_all(EDSTITModel.t(), Path.t(), keyword()) :: map()
  def write_all(%EDSTITModel{} = model, output_dir, opts \\ []) do
    catalog = GraphViewCatalog.build(model, include_empty: true)
    full_id = GraphViewCatalog.full!(catalog).id
    existing_full = Keyword.get(opts, :existing_full)
    views_dir = Path.join(output_dir, "graph_views")

    File.mkdir_p!(views_dir)

    views =
      catalog.views
      |> Enum.sort_by(fn {id, view} ->
        {length(view.selected_modalities), id}
      end)
      |> Enum.with_index()
      |> Map.new(fn {{id, view}, index} ->
        paths =
          if id == full_id and is_map(existing_full) do
            %{
              graph_dot_file: existing_full.graph_dot_file,
              graph_svg_file: existing_full.graph_svg_file,
              graph_tikz_file: existing_full.graph_tikz_file
            }
          else
            basename =
              "view-" <>
                String.pad_leading(Integer.to_string(index), 3, "0")

            render_view(
              model,
              catalog,
              view.selected_modalities,
              Path.join(views_dir, basename),
              opts
            )
          end

        {id, Map.put(paths, :modalities, view.selected_modalities)}
      end)

    %{
      filter_keys: catalog.filter_keys,
      default_view: full_id,
      views: views
    }
  end

  defp render_view(model, catalog, modalities, basename, opts) do
    dot_path = basename <> ".dot"
    svg_path = basename <> ".svg"
    tikz_path = basename <> ".tex"

    render_opts =
      opts
      |> Keyword.delete(:existing_full)
      |> Keyword.put(:view_catalog, catalog)
      |> Keyword.put(:modalities, modalities)

    graph_dot_file = Render.write_dot(model, dot_path, render_opts)

    graph_svg_file =
      Render.render_dot(graph_dot_file,
        fmt: "svg",
        output_path: svg_path
      )

    graph_tikz_file = Render.write_tikz(model, tikz_path, render_opts)

    %{
      graph_dot_file: graph_dot_file,
      graph_svg_file: graph_svg_file,
      graph_tikz_file: graph_tikz_file
    }
  end
end
