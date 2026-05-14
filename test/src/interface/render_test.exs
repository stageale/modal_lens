defmodule Src.Core.RenderTest do
  use ExUnit.Case

  alias Src.Core.Model
  alias Src.Core.Render

  test "writes GraphViz DOT file" do
    model = %Model{
      kind: :countermodel,
      cardinality: 2,
      relation_name: "R",
      initial_world: 0,
      edges: MapSet.new([{0, 1}, {1, 1}]),
      valuations: %{
        "go" => [true, false]
      }
    }

    path = tmp_path("model.dot")

    written_path = Render.write_dot(model, path, atoms: ["go"])
    content = File.read!(written_path)

    assert content =~ "digraph KripkeModel"
    assert content =~ "rankdir=LR"
    assert content =~ "w0 [label=\"i1: go\"]"
    assert content =~ "w1 [label=\"i2: ¬go\"]"
    assert content =~ "init -> w0"
    assert content =~ "w0 -> w1;"
    assert content =~ "w1 -> w1;"
  end

  test "escapes LaTeX special characters" do
    assert Render.latex_escape("¬go_a") == "$\\neg$go\\_a"
    assert Render.latex_escape("a&b") == "a\\&b"
    assert Render.latex_escape("x%y") == "x\\%y"
  end

  test "writes TikZ file" do
    model = %Model{
      kind: :countermodel,
      cardinality: 1,
      relation_name: "R",
      initial_world: 0,
      edges: MapSet.new([{0, 0}]),
      valuations: %{
        "go" => [true]
      }
    }

    path = tmp_path("model.tex")

    written_path = Render.write_tikz(model, path, atoms: ["go"])
    content = File.read!(written_path)

    assert content =~ "\\documentclass"
    assert content =~ "\\begin{tikzpicture}"
    assert content =~ "\\node[world] (w0)"
    assert content =~ "i1: go"
    assert content =~ "\\path[->,loop above] (w0) edge (w0);"
    assert content =~ "\\end{document}"
  end

  defp tmp_path(filename) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_render_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    Path.join(dir, filename)
  end
end
