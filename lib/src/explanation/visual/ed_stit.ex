defmodule Src.Explanation.Visual.EDSTIT do
  @moduledoc """
  Renders finite Epistemic Deontic STIT models.

  Worlds are shared by all modalities. Accessibility edges are rendered
  separately and labelled by their semantic modality so that overlapping
  settledness, STIT, ought, and belief structure remains visible.
  """

  alias Src.Core.Model
  alias Src.Core.Model.EDSTIT, as: EDSTITModel
  alias Src.Core.Model.Modality

  @doc "Writes an ED-STIТ model as GraphViz DOT."
  @spec write_dot(EDSTITModel.t(), Path.t(), keyword()) :: String.t()
  def write_dot(%EDSTITModel{} = model, path, opts \\ []) do
    atoms = Keyword.get(opts, :atoms)
    path = to_string(path)

    mkdir_parent!(path)

    lines =
      [
        "digraph #{Model.graph_name(model)} {",
        "  rankdir=LR;",
        "  node [shape=circle, fontsize=10, fixedsize=true, width=1.35];",
        ""
      ] ++
        dot_world_lines(model, atoms) ++
        [
          "",
          "  init [shape=plaintext, label=\"actual\"];",
          "  init -> w#{Model.designated_world(model)} [penwidth=2];",
          ""
        ] ++
        dot_modality_lines(model) ++
        ["}"]

    File.write!(path, Enum.join(lines, "\n") <> "\n")
    path
  end

  @doc "Writes an ED-STIТ model as a standalone TikZ document."
  @spec write_tikz(EDSTITModel.t(), Path.t(), keyword()) :: String.t()
  def write_tikz(%EDSTITModel{} = model, path, opts \\ []) do
    atoms = Keyword.get(opts, :atoms)
    path = to_string(path)

    mkdir_parent!(path)

    lines =
      [
        ~S(\documentclass[tikz,border=3mm]{standalone}),
        ~S(\usetikzlibrary{calc}),
        ~S(\tikzset{world/.style={circle,draw,minimum size=1.5cm,inner sep=1pt,align=center,font=\small}}),
        "",
        ~S(\begin{document}),
        ~S(\begin{tikzpicture}[>=stealth]),
        ""
      ] ++
        tikz_world_lines(model, atoms) ++
        [""] ++
        tikz_modality_lines(model) ++
        [
          "",
          "  \\draw[->,thick] ($ (w#{Model.designated_world(model)}.west)+(-8mm,0) $) -- (w#{Model.designated_world(model)}.west);",
          ~S(\end{tikzpicture}),
          ~S(\end{document})
        ]

    File.write!(path, Enum.join(lines, "\n") <> "\n")
    path
  end

  defp dot_world_lines(model, atoms) do
    Enum.map(Model.world_indices(model), fn world ->
      label =
        model
        |> Model.label_for_world(world, atoms)
        |> dot_escape()

      ~s(  w#{world} [label="#{label}"];)
    end)
  end

  defp dot_modality_lines(%EDSTITModel{modalities: modalities}) do
    modalities
    |> Enum.sort_by(&Modality.sort_key/1)
    |> Enum.flat_map(fn modality ->
      modality.accessibility
      |> Enum.sort()
      |> Enum.map(fn {source, target} ->
        "  w#{source} -> w#{target} [#{dot_modality_attributes(modality)}];"
      end)
    end)
  end

  defp dot_modality_attributes(%Modality{} = modality) do
    label = modality |> modality_label() |> dot_escape()

    case modality.kind do
      :settledness -> ~s(label="#{label}", style="solid")
      :stit -> ~s(label="#{label}", penwidth=2)
      :ought -> ~s(label="#{label}", style="dashed")
      :belief -> ~s(label="#{label}", style="dotted")
    end
  end

  defp tikz_world_lines(model, atoms) do
    worlds = Model.world_indices(model)
    count = length(worlds)
    radius = if count > 1, do: 3.0, else: 0.0

    worlds
    |> Enum.with_index()
    |> Enum.map(fn {world, index} ->
      angle = if count > 0, do: 2.0 * :math.pi() * index / count, else: 0.0
      x = radius * :math.cos(angle)
      y = radius * :math.sin(angle)

      label =
        model
        |> Model.label_for_world(world, atoms)
        |> latex_escape()

      "  \\node[world] (w#{world}) at (#{format_float(x)},#{format_float(y)}) {#{label}};"
    end)
  end

  defp tikz_modality_lines(%EDSTITModel{modalities: modalities}) do
    modalities
    |> Enum.sort_by(&Modality.sort_key/1)
    |> Enum.flat_map(fn modality ->
      modality.accessibility
      |> Enum.sort()
      |> Enum.map(fn {source, target} ->
        tikz_modality_edge(modality, source, target)
      end)
    end)
  end

  defp tikz_modality_edge(%Modality{} = modality, source, target) do
    options = tikz_modality_options(modality, source == target)
    label = modality |> modality_label() |> latex_escape()

    "  \\path[#{options}] (w#{source}) edge " <>
      "node[midway,fill=white,inner sep=1pt,font=\\scriptsize]{#{label}} " <>
      "(w#{target});"
  end

  defp tikz_modality_options(%Modality{kind: kind}, true) do
    loop =
      case kind do
        :settledness -> "loop above"
        :stit -> "loop right"
        :ought -> "loop below"
        :belief -> "loop left"
      end

    Enum.join(["->", modality_tikz_style(kind), loop], ",")
  end

  defp tikz_modality_options(%Modality{kind: kind}, false) do
    bend =
      case kind do
        :settledness -> nil
        :stit -> "bend left=12"
        :ought -> "bend right=12"
        :belief -> "bend left=24"
      end

    ["->", modality_tikz_style(kind), bend]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end

  defp modality_tikz_style(:settledness), do: "solid"
  defp modality_tikz_style(:stit), do: "very thick"
  defp modality_tikz_style(:ought), do: "dashed"
  defp modality_tikz_style(:belief), do: "dotted"

  defp modality_label(%Modality{kind: :settledness}), do: "settled"
  defp modality_label(%Modality{kind: :stit, agent: agent}), do: "STIT(#{agent})"
  defp modality_label(%Modality{kind: :ought, agent: agent}), do: "Ought(#{agent})"
  defp modality_label(%Modality{kind: :belief, agent: agent}), do: "Belief(#{agent})"

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
    |> Enum.map(fn char -> Map.get(replacements, char, char) end)
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
