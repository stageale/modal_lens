defmodule Src.Core.Render do
  alias Src.Core.Model

  def write_dot(%Model{} = model, path, opts \\ []) do
    atoms = Keyword.get(opts, :atoms)
    highlight = Keyword.get(opts, :highlight)
    path = to_string(path)

    mkdir_parent!(path)

    lines =
      [
        "digraph KripkeModel {",
        "  rankdir=LR;",
        "  node [shape=circle, fontsize=10, fixedsize=true, width=1.35];",
        ""
      ] ++
        dot_world_lines(model, atoms, highlight) ++
        [
          "",
          "  init [shape=plaintext, label=\"start\"];",
          "  init -> w#{model.initial_world} [penwidth=2];",
          ""
        ] ++
        dot_edge_lines(model, highlight) ++
        ["}"]

    File.write!(path, Enum.join(lines, "\n") <> "\n")
    path
  end

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
      System.cmd(dot_exe, ["-T#{fmt}", dot_path, "-o", out],
        stderr_to_stdout: true
      )

    if status != 0 do
      raise "GraphViz dot failed with exit status #{status}."
    end

    out
  end

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

  def write_tikz(%Model{} = model, path, opts \\ []) do
    atoms = Keyword.get(opts, :atoms)
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
        tikz_world_lines(model, atoms, radius) ++
        [""] ++
        tikz_edge_lines(model) ++
        [
          "",
          "  \\draw[->,thick] ($ (w#{model.initial_world}.west)+(-8mm,0) $) -- (w#{model.initial_world}.west);",
          ~S(\end{tikzpicture}),
          ~S(\end{document})
        ]

    File.write!(path, Enum.join(lines, "\n") <> "\n")
    path
  end

  def compile_tex(tex_path, opts \\ []) do
    engine = Keyword.get(opts, :engine, "pdflatex")

    exe =
      System.find_executable(engine) ||
        raise "LaTeX executable '#{engine}' was not found. Install TeX Live or omit --compile."

    tex_path = to_string(tex_path)
    out_dir = Path.dirname(tex_path)

    {_output, status} =
      System.cmd(
        exe,
        ["-interaction=nonstopmode", "-output-directory=#{out_dir}", tex_path],
        stderr_to_stdout: true
      )

    if status != 0 do
      raise "LaTeX failed with exit status #{status}."
    end

    Path.rootname(tex_path) <> ".pdf"
  end

  defp dot_world_lines(model, atoms, highlight) do
    for i <- world_indices(model) do
      label =
        model
        |> Model.label_for_world(i, atoms)
        |> dot_escape()

      attrs =
        if responsible_world?(highlight, i) do
          ~s/[label="#{label}", color="red", penwidth=2]/
        else
          ~s/[label="#{label}"]/
        end

      "  w#{i} #{attrs};"
    end
  end

  defp dot_edge_lines(model, highlight) do
    proper =
      model.edges
      |> Enum.filter(fn {a, b} -> a != b end)
      |> Enum.sort()
      |> Enum.map(fn edge -> dot_edge_line(edge, highlight) end)

    loops =
      model.edges
      |> Enum.filter(fn {a, b} -> a == b end)
      |> Enum.sort()
      |> Enum.map(fn edge -> dot_edge_line(edge, highlight) end)

    missing =
      highlight
      |> missing_edges()
      |> Enum.reject(fn edge -> edge in model.edges end)
      |> Enum.sort()
      |> Enum.map(&dot_missing_edge_line/1)

    proper ++ loops ++ missing
  end

  defp dot_edge_line({a, b} = edge, highlight) do
    attrs =
      cond do
        responsible_edge?(highlight, edge) ->
          ~s/ [color="red", fontcolor="red", penwidth=2]/
        true ->
          ""
      end

    " w#{a} -> w#{b}#{attrs};"
  end

  defp dot_missing_edge_line({a, b}) do
    ~s/ w#{a} -> w#{b} [color="red", fontcolor="red", style="dashed", penwidth=2];/
  end

  defp responsible_edge?(nil, _edge), do: false

  defp responsible_edge?(highlight, edge) do
    MapSet.member?(highlight.responsible_edges, edge)
  end

  defp responsible_world?(nil, _world), do: false

  defp responsible_world?(highlight, world) do
    MapSet.member?(highlight.responsible_worlds, world)
  end

  defp missing_edges(nil), do: []

  defp missing_edges(highlight) do
    MapSet.to_list(highlight.missing_edges)
  end

  defp tikz_world_lines(model, atoms, radius) do
    for i <- world_indices(model) do
      angle = 360 * i / max(1, model.cardinality)

      label =
        model
        |> Model.label_for_world(i, atoms)
        |> latex_escape()

      "  \\node[world] (w#{i}) at (#{format_float(angle)}:#{format_float(radius)}cm) {#{label}};"
    end
  end

  defp tikz_edge_lines(model) do
    proper =
      model.edges
      |> Enum.filter(fn {a, b} -> a != b end)
      |> Enum.sort()
      |> Enum.map(fn {a, b} -> "  \\draw[->] (w#{a}) -- (w#{b});" end)

    loops =
      model.edges
      |> Enum.filter(fn {a, b} -> a == b end)
      |> Enum.sort()
      |> Enum.map(fn {a, b} ->
        pos =
          if rem(a, 2) == 0 do
            "above"
          else
            "below"
          end

        "  \\path[->,loop #{pos}] (w#{a}) edge (w#{b});"
      end)

    proper ++ loops
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

  defp world_indices(%Model{cardinality: cardinality}) when cardinality > 0 do
    0..(cardinality - 1)
  end

  defp world_indices(%Model{}) do
    []
  end

  defp format_float(number) do
    number
    |> Kernel.*(1.0)
    |> :erlang.float_to_binary(decimals: 2)
  end
end
