defmodule Src.Explanation.Visual.EDSTIT do
  @moduledoc "Renders ED-STIT models from precomputed modal graph views."

  alias Src.Core.Model
  alias Src.Core.Model.EDSTIT, as: EDSTITModel
  alias Src.Explanation.Visual.GraphView
  alias Src.Explanation.Visual.GraphView.{RelationView, ViewEdge}
  alias Src.Explanation.Visual.GraphViewCatalog
  alias Src.Explanation.Visual.Palette
  alias Src.Explanation.Visual.WorldLabel

  @agent_colors ~w(1F77B4 D62728 2CA02C 9467BD FF7F0E 17BECF)

  @doc "Writes a selected ED-STIT view as GraphViz DOT."
  @spec write_dot(EDSTITModel.t(), Path.t(), keyword()) :: String.t()
  def write_dot(%EDSTITModel{} = model, path, opts \\ []) do
    view = selected_view(model, opts)
    colors = agent_colors(model)
    atoms = Keyword.get(opts, :atoms)
    highlight = Keyword.get(opts, :highlight)
    palette = Keyword.get(opts, :palette, Palette.default())
    path = to_string(path)
    mkdir_parent!(path)

    lines =
      [
        "digraph #{Model.graph_name(model)} {",
        "  rankdir=LR;",
        "  node [shape=circle, fontsize=10, fixedsize=false, width=1.35, margin=0.08];",
        ""
      ] ++
        dot_world_lines(model, view, atoms, highlight, palette) ++
        [
          "",
          "  init [shape=plaintext, label=\"actual\"];",
          "  init -> w#{view.designated_world} [penwidth=2];",
          ""
        ] ++
        dot_relation_lines(view, colors, highlight) ++
        dot_legend_lines(view, colors) ++
        ["}"]

    File.write!(path, Enum.join(lines, "\n") <> "\n")
    path
  end

  @doc "Writes a selected ED-STIT view as a standalone TikZ document."
  @spec write_tikz(EDSTITModel.t(), Path.t(), keyword()) :: String.t()
  def write_tikz(%EDSTITModel{} = model, path, opts \\ []) do
    view = selected_view(model, opts)
    colors = agent_colors(model)
    atoms = Keyword.get(opts, :atoms)
    highlight = Keyword.get(opts, :highlight)
    palette = Keyword.get(opts, :palette, Palette.default())
    path = to_string(path)
    mkdir_parent!(path)

    lines =
      [
        ~S(\documentclass[tikz,border=3mm]{standalone}),
        ~S(\usetikzlibrary{calc}),
        ~S(\tikzset{world/.style={circle,draw,minimum size=1.5cm,inner sep=1pt,align=center,font=\small}})
      ] ++
        tikz_colors(colors) ++
        [
          "",
          ~S(\begin{document}),
          ~S(\begin{tikzpicture}[>=stealth]),
          ""
        ] ++
        tikz_world_lines(model, view, atoms, highlight, palette) ++
        [""] ++
        tikz_relation_lines(view, colors, highlight) ++
        [
          "",
          "  \\draw[->,thick] ($ (w#{view.designated_world}.west)+(-8mm,0) $) -- (w#{view.designated_world}.west);"
        ] ++
        tikz_legend_lines(view, colors) ++
        [
          ~S(\end{tikzpicture}),
          ~S(\end{document})
        ]

    File.write!(path, Enum.join(lines, "\n") <> "\n")
    path
  end

  defp selected_view(model, opts) do
    catalog =
      Keyword.get_lazy(opts, :view_catalog, fn ->
        GraphViewCatalog.build(model)
      end)

    case Keyword.get(opts, :modalities) do
      nil -> GraphViewCatalog.full!(catalog)
      selected -> GraphViewCatalog.fetch!(catalog, selected)
    end
  end

  defp dot_world_lines(model, %GraphView{worlds: worlds}, atoms, highlight, palette) do
    Enum.map(worlds, fn world ->
      label =
        model
        |> WorldLabel.lines(world, atoms)
        |> Enum.map(&dot_escape/1)
        |> Enum.join("\\n")

      attrs =
        case world_score(highlight, world) do
          {:ok, score} ->
            rgb = Palette.color(palette, score)
            fill = Palette.hex(palette, score)
            font = contrast_color(rgb)
            penwidth = score_width(score, 1.0, 3.0)

            ~s(label="#{label}", style="filled", fillcolor="#{fill}", color="#222222", fontcolor="#{font}", penwidth=#{format_float(penwidth)})

          :error ->
            ~s(label="#{label}")
        end

      "  w#{world} [#{attrs}];"
    end)
  end

  defp dot_relation_lines(%GraphView{relations: relations}, colors, highlight) do
    Enum.flat_map(relations, fn relation ->
      Enum.map(relation.edges, fn edge ->
        direction =
          case edge.direction do
            :forward -> "forward"
            :both -> "both"
            :undirected -> "none"
          end

        penwidth =
          case view_edge_score(highlight, edge) do
            {:ok, score} -> max(dot_width(relation.kind) * 1.0, score_width(score, 2.5, 5.0))
            :error -> dot_width(relation.kind)
          end

        attrs =
          ~s(color="#{relation_color(colors, relation)}", style="#{dot_style(relation.kind)}", dir="#{direction}", penwidth=#{format_float(penwidth)})

        "  w#{edge.source} -> w#{edge.target} [#{attrs}];"
      end)
    end)
  end

  defp dot_legend_lines(%GraphView{relations: relations}, colors) do
    entries =
      relations
      |> Enum.with_index()
      |> Enum.flat_map(fn {relation, index} ->
        agent =
          if relation.agent,
            do: " (#{relation.agent})",
            else: ""

        label =
          dot_escape("#{relation.kind}#{agent}: #{property_names(relation)}")

        color = relation_color(colors, relation)

        [
          ~s(    legend#{index}a [shape=point, width=0.01, label=""];),
          ~s(    legend#{index}b [shape=plaintext, label="#{label}"];),
          ~s(    legend#{index}a -> legend#{index}b [color="#{color}", style="#{dot_style(relation.kind)}", penwidth=#{dot_width(relation.kind)}];)
        ]
      end)

    [
      "",
      "  subgraph cluster_legend {",
      "    label=\"Legend: style = modality, color = agent\";"
    ] ++ entries ++ ["  }"]
  end

  defp tikz_colors(colors) do
    colors
    |> Enum.map(fn {_agent, {index, hex}} ->
      "\\definecolor{agent#{index}}{HTML}{#{hex}}"
    end)
    |> Enum.sort()
  end

  defp tikz_world_lines(model, %GraphView{worlds: worlds}, atoms, highlight, palette) do
    count = length(worlds)
    radius = if count > 1, do: 3.0, else: 0.0

    worlds
    |> Enum.with_index()
    |> Enum.map(fn {world, index} ->
      angle =
        if count > 0,
          do: 2.0 * :math.pi() * index / count,
          else: 0.0

      x = radius * :math.cos(angle)
      y = radius * :math.sin(angle)

      label =
        model
        |> WorldLabel.lines(world, atoms)
        |> Enum.map(&latex_escape/1)
        |> Enum.join("\\\\")

      options =
        case world_score(highlight, world) do
          {:ok, score} ->
            rgb = Palette.color(palette, score)
            text_color = contrast_color(rgb)
            line_width = score_width(score, 0.8, 2.4)

            "world,fill=#{tikz_rgb(rgb)},text=#{text_color},line width=#{format_float(line_width)}pt"

          :error ->
            "world"
        end

      "  \\node[#{options}] (w#{world}) at (#{format_float(x)},#{format_float(y)}) {#{label}};"
    end)
  end

  defp tikz_relation_lines(%GraphView{relations: relations}, colors, highlight) do
    Enum.flat_map(relations, fn relation ->
      Enum.map(relation.edges, fn %ViewEdge{} = edge ->
        arrow =
          case edge.direction do
            :forward -> "->"
            :both -> "<->"
            :undirected -> "-"
          end

        loop =
          if edge.source == edge.target,
            do: ",loop above",
            else: ""

        style = tikz_style(relation.kind)
        color = tikz_color(colors, relation)

        width =
          case view_edge_score(highlight, edge) do
            {:ok, score} -> ",line width=#{format_float(score_width(score, 1.2, 3.2))}pt"
            :error -> ""
          end

        "  \\path[#{arrow},#{style},draw=#{color}#{width}#{loop}] " <>
          "(w#{edge.source}) edge (w#{edge.target});"
      end)
    end)
  end

  defp tikz_legend_lines(%GraphView{relations: relations}, colors) do
    relations
    |> Enum.with_index()
    |> Enum.flat_map(fn {relation, index} ->
      agent =
        if relation.agent,
          do: " (#{relation.agent})",
          else: ""

      label =
        latex_escape("#{relation.kind}#{agent}: #{property_names(relation)}")

      y = -4.1 - index * 0.55
      color = tikz_color(colors, relation)

      [
        "  \\draw[->,#{tikz_style(relation.kind)},draw=#{color}] " <>
          "(-3.5,#{format_float(y)}) -- (-2.7,#{format_float(y)});",
        "  \\node[anchor=west] at (-2.5,#{format_float(y)}) {#{label}};"
      ]
    end)
  end

  defp property_names(%RelationView{properties: properties}) do
    [:reflexive, :symmetric, :transitive]
    |> Enum.filter(&Map.get(properties, &1))
    |> case do
      [] -> "no global R/S/T properties"
      names -> Enum.join(names, ", ")
    end
  end

  # The assignment uses every agent in the original model, so a filter
  # selection does not change an agent's color.
  defp agent_colors(%EDSTITModel{} = model) do
    (model.agents ++ Enum.map(model.modalities, & &1.agent))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.with_index()
    |> Map.new(fn {agent, index} ->
      hex =
        Enum.at(
          @agent_colors,
          rem(index, length(@agent_colors))
        )

      {agent, {index, hex}}
    end)
  end

  defp relation_color(_colors, %RelationView{agent: nil}),
    do: "#555555"

  defp relation_color(colors, %RelationView{agent: agent}) do
    {_index, hex} = Map.fetch!(colors, agent)
    "#" <> hex
  end

  defp tikz_color(_colors, %RelationView{agent: nil}),
    do: "black!65"

  defp tikz_color(colors, %RelationView{agent: agent}) do
    {index, _hex} = Map.fetch!(colors, agent)
    "agent#{index}"
  end

  defp dot_style(:settledness), do: "solid"
  defp dot_style(:stit), do: "solid"
  defp dot_style(:ought), do: "dashed"
  defp dot_style(:belief), do: "dotted"

  defp dot_width(:stit), do: 2
  defp dot_width(_), do: 1

  defp tikz_style(:settledness), do: "solid"
  defp tikz_style(:stit), do: "very thick"
  defp tikz_style(:ought), do: "dashed"
  defp tikz_style(:belief), do: "dotted"

  defp world_score(nil, _world), do: :error

  defp world_score(highlight, world) do
    Map.fetch(highlight.world_scores, world)
  end

  defp view_edge_score(nil, _edge), do: :error

  defp view_edge_score(highlight, %ViewEdge{source: source, target: target, direction: :forward}) do
    Map.fetch(highlight.edge_scores, {source, target})
  end

  defp view_edge_score(highlight, %ViewEdge{source: source, target: target}) do
    [{source, target}, {target, source}]
    |> Enum.flat_map(fn edge ->
      case Map.fetch(highlight.edge_scores, edge) do
        {:ok, score} -> [score]
        :error -> []
      end
    end)
    |> case do
      [] -> :error
      scores -> {:ok, Enum.max(scores)}
    end
  end

  defp score_width(score, minimum, maximum) do
    minimum + score * (maximum - minimum)
  end

  defp contrast_color({red, green, blue}) do
    luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
    if luminance >= 145, do: "black", else: "white"
  end

  defp tikz_rgb({red, green, blue}) do
    "{rgb,255:red,#{red};green,#{green};blue,#{blue}}"
  end

  defp dot_escape(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  defp latex_escape(string) do
    replacements = %{
      "\\" => "\\textbackslash{}",
      "_" => "\\_",
      "&" => "\\&",
      "%" => "\\%",
      "$" => "\\$",
      "#" => "\\#",
      "{" => "\\{",
      "}" => "\\}",
      "¬" => "$\\neg$"
    }

    string
    |> String.graphemes()
    |> Enum.map(&Map.get(replacements, &1, &1))
    |> Enum.join()
  end

  defp mkdir_parent!(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()
  end

  defp format_float(number) do
    number
    |> Kernel.*(1.0)
    |> :erlang.float_to_binary(decimals: 2)
  end
end
