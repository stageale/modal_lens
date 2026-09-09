defmodule Src.Explanation.Visual.Render do
  @moduledoc """
  Renders finite models as GraphViz DOT or TikZ diagrams.

  The module can also invoke GraphViz and LaTeX to compile the generated
  source files into image or PDF artifacts.
  """

  alias Src.Core.Model
  alias Src.Explanation.Visual.Palette

  @doc "Writes a model visualization as a GraphViz DOT file."
  @spec write_dot(Model.model(), Path.t()) :: String.t()
  @spec write_dot(Model.model(), Path.t(), keyword()) :: String.t()
  def write_dot(model, path, opts \\ []) do
    Model.assert_supported!(model)

    atoms = Keyword.get(opts, :atoms)
    highlight = Keyword.get(opts, :highlight)
    palette = Keyword.get(opts, :palette, Palette.default())
    path = to_string(path)

    mkdir_parent!(path)

    lines =
      [
        "digraph #{Model.graph_name(model)} {",
        "  rankdir=LR;",
        "  node [shape=circle, fontsize=10, fixedsize=true, width=1.35];",
        ""
      ] ++
        dot_world_lines(model, atoms, highlight, palette) ++
        [
          "",
          "  init [shape=plaintext, label=\"start\"];",
          "  init -> w#{Model.designated_world(model)} [penwidth=2];",
          ""
        ] ++
        dot_edge_lines(model, highlight, palette) ++
        ["}"]

    File.write!(path, Enum.join(lines, "\n") <> "\n")
    path
  end

  @doc "Renders an existing DOT file using the GraphViz `dot` executable."
  @spec render_dot(Path.t()) :: String.t()
  @spec render_dot(Path.t(), keyword()) :: String.t()
  def render_dot(dot_path, opts \\ []) do
    fmt = Keyword.get(opts, :fmt, "png")
    output_path = Keyword.get(opts, :output_path)

    dot_exe =
      System.find_executable("dot") ||
        raise "GraphViz executable 'dot' was not found. Install graphviz or omit --render."

    dot_path = to_string(dot_path)
    out = output_path || Path.rootname(dot_path) <> ".#{fmt}"
    mkdir_parent!(out)

    {_output, status} =
      System.cmd(dot_exe, ["-T#{fmt}", dot_path, "-o", out], stderr_to_stdout: true)

    if status != 0 do
      raise "GraphViz dot failed with exit status #{status}."
    end

    out
  end

  @doc "Escapes text for use inside generated LaTeX content."
  @spec latex_escape(String.t()) :: String.t()
  def latex_escape(string) do
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
    |> Enum.map(fn char -> Map.get(replacements, char, char) end)
    |> Enum.join()
  end

  @doc "Writes a model visualization as a standalone TikZ document."
  @spec write_tikz(Model.model(), Path.t()) :: String.t()
  @spec write_tikz(Model.model(), Path.t(), keyword()) :: String.t()
  def write_tikz(model, path, opts \\ []) do
    Model.assert_supported!(model)

    d_world = Model.designated_world(model)
    atoms = Keyword.get(opts, :atoms)
    highlight = Keyword.get(opts, :highlight)
    palette = Keyword.get(opts, :palette, Palette.default())
    path = to_string(path)

    mkdir_parent!(path)

    radius =
      if model.cardinality > 1 do
        3.0
      else
        0.0
      end

    lines =
      [
        ~S(\documentclass[tikz,border=3mm]{standalone}),
        ~S(\usetikzlibrary{calc,positioning}),
        ~S(\tikzset{world/.style={circle,draw,minimum size=1.5cm,inner sep=1pt,align=center,font=\small}}),
        "",
        ~S(\begin{document}),
        ~S(\begin{tikzpicture}[>=stealth]),
        ""
      ] ++
        tikz_world_lines(model, atoms, radius, highlight, palette) ++
        [""] ++
        tikz_edge_lines(model, highlight, palette) ++
        [
          "",
          "  \\draw[->,thick] ($ (w#{d_world}.west)+(-8mm,0) $) -- (w#{d_world}.west);",
          ~S(\end{tikzpicture}),
          ~S(\end{document})
        ]

    File.write!(path, Enum.join(lines, "\n") <> "\n")
    path
  end

  @doc "Compiles a generated TeX file and returns the resulting PDF path."
  @spec compile_tex(Path.t()) :: String.t()
  @spec compile_tex(Path.t(), keyword()) :: String.t()
  def compile_tex(tex_path, opts \\ []) do
    engine = Keyword.get(opts, :engine, "pdflatex")

    exe =
      System.find_executable(engine) ||
        raise "LaTeX executable '#{engine}' was not found. Install TeX Live or omit --compile."

    tex_path = to_string(tex_path)
    out_dir = Path.dirname(tex_path)
    tex_file = Path.basename(tex_path)

    {_output, status} =
      System.cmd(
        exe,
        [
          "-interaction=nonstopmode",
          "-halt-on-error",
          "-file-line-error",
          "-output-directory=#{out_dir}",
          tex_file
        ],
        cd: out_dir,
        stderr_to_stdout: true
      )

    if status != 0 do
      raise "LaTeX failed with exit status #{status}."
    end

    Path.rootname(tex_path) <> ".pdf"
  end

  defp dot_world_lines(model, atoms, highlight, palette) do
    for i <- Model.world_indices(model) do
      label =
        model
        |> Model.label_for_world(i, atoms)
        |> dot_escape()

      attrs =
        dot_world_attributes(label, highlight, palette, i)

      "  w#{i} #{attrs};"
    end
  end

  defp dot_world_attributes(label, highlight, palette, world) do
    case world_score(highlight, world) do
      {:ok, score} ->
        rgb = Palette.color(palette, score)
        fill = Palette.hex(palette, score)
        font = contrast_color(rgb)
        penwidth = score_width(score, 1.0, 3.0)

        ~s/[label="#{label}", style="filled", fillcolor="#{fill}", color="#222222", fontcolor="#{font}", penwidth=#{format_float(penwidth)}]/

      :error ->
        ~s/[label="#{label}"]/
    end
  end

  defp dot_edge_lines(model, highlight, palette) do
    model.edges
    |> Enum.sort()
    |> Enum.map(fn edge -> dot_edge_line(edge, highlight, palette) end)
  end

  defp dot_edge_line({a, b} = edge, highlight, palette) do
    attrs =
      case edge_score(highlight, edge) do
        {:ok, score} ->
          color = Palette.hex(palette, score)
          penwidth = score_width(score, 1.0, 4.0)

          ~s/ [color="#{color}", penwidth=#{format_float(penwidth)}]/

        :error ->
          ""
      end

    "  w#{a} -> w#{b}#{attrs};"
  end

  defp tikz_world_lines(model, atoms, radius, highlight, palette) do
    for i <- Model.world_indices(model) do
      angle = 360 * i / max(1, model.cardinality)

      label =
        model
        |> Model.label_for_world(i, atoms)
        |> latex_escape()

      options = tikz_world_options(highlight, palette, i)

      "  \\node[#{options}] (w#{i}) at (#{format_float(angle)}:#{format_float(radius)}cm) {#{label}};"
    end
  end

  defp tikz_world_options(highlight, palette, world) do
    case world_score(highlight, world) do
      {:ok, score} ->
        rgb = Palette.color(palette, score)
        text_color = contrast_color(rgb)
        line_width = score_width(score, 0.8, 2.4)

        [
          "world",
          "fill=#{tikz_rgb(rgb)}",
          "text=#{text_color}",
          "line width=#{format_float(line_width)}pt"
        ]
        |> Enum.join(", ")

      :error ->
        "world"
    end
  end

  defp tikz_edge_lines(model, highlight, palette) do
    model.edges
    |> Enum.sort()
    |> Enum.map(fn {a, b} = edge ->
      options =
        if a != b do
          tikz_edge_options(edge, highlight, palette)
        else
          loop_pos =
            if rem(a, 2) == 0 do
              "above"
            else
              "below"
            end

          tikz_edge_options(edge, highlight, palette, ["loop #{loop_pos}"])
        end

      "  \\path[#{options}] (w#{a}) edge (w#{b});"
    end)
  end

  defp tikz_edge_options(edge, highlight, palette, additional_options \\ []) do
    base_options = ["->"] ++ additional_options

    options =
      case edge_score(highlight, edge) do
        {:ok, score} ->
          rgb = Palette.color(palette, score)
          line_width = score_width(score, 0.7, 3.2)

          base_options ++ ["draw=#{tikz_rgb(rgb)}", "line width=#{format_float(line_width)}pt"]

        :error ->
          base_options
      end

    Enum.join(options, ",")
  end

  defp dot_escape(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
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

  defp world_score(nil, _world), do: :error

  defp world_score(highlight, world) do
    highlight.world_scores
    |> Map.fetch(world)
  end

  defp edge_score(nil, _edge), do: :error

  defp edge_score(highlight, edge) do
    highlight.edge_scores
    |> Map.fetch(edge)
  end

  defp score_width(score, minimum, maximum) do
    minimum + score * (maximum - minimum)
  end

  defp contrast_color({red, green, blue}) do
    luminance =
      0.2126 * red + 0.7152 * green + 0.0722 * blue

    if luminance >= 145 do
      "black"
    else
      "white"
    end
  end

  defp tikz_rgb({red, green, blue}) do
    "{rgb,255:red,#{red};green,#{green};blue,#{blue}}"
  end
end
