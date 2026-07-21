defmodule Src.Core.RenderTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.DDL
  alias Src.Core.Model.SDL
  alias Src.Core.Render
  alias Src.VisualExplanations.Highlight

  test "writes a highlighted SDL GraphViz DOT file" do
    model = %SDL{
      kind: :countermodel,
      cardinality: 2,
      relation_name: "R",
      initial_world: 0,
      edges: MapSet.new([{0, 1}, {1, 1}]),
      valuations: %{"go" => [true, false]}
    }

    highlight =
      Highlight.new(
        responsible_worlds: [0],
        responsible_edges: [{0, 1}],
        missing_edges: [{1, 0}]
      )

    path = tmp_path("model.dot")
    written_path = Render.write_dot(model, path, atoms: ["go"], highlight: highlight)
    content = File.read!(written_path)

    assert content =~ "digraph KripkeModel"
    assert content =~ ~s(w0 [label="i1: go", color="red", penwidth=2])
    assert content =~ ~s(w1 [label="i2: \\\\<not>go"])
    assert content =~ "init -> w0"
    assert content =~ ~s(w0 -> w1 [color="red", fontcolor="red", penwidth=2])
    assert content =~ ~s(w1 -> w0 [color="red", fontcolor="red", style="dashed")
  end

  test "uses DDL graph and actual-world semantics" do
    model = %DDL{
      kind: :model,
      cardinality: 1,
      relation_name: "R",
      actual_world: 0,
      edges: MapSet.new(),
      valuations: %{}
    }

    path = Render.write_dot(model, tmp_path("ddl.dot"))
    content = File.read!(path)

    assert content =~ "digraph PreferenceModel"
    assert content =~ "init -> w0"
  end

  test "escapes LaTeX special characters" do
    assert Render.latex_escape("¬go_a") == "$\\neg$go\\_a"
    assert Render.latex_escape("a&b") == "a\\&b"
    assert Render.latex_escape("x%y") == "x\\%y"
  end

  test "writes a TikZ file" do
    model = %SDL{
      kind: :countermodel,
      cardinality: 1,
      relation_name: "R",
      initial_world: 0,
      edges: MapSet.new([{0, 0}]),
      valuations: %{"go" => [true]}
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

  test "reports a missing LaTeX engine before compilation" do
    assert_raise RuntimeError, ~r/LaTeX executable/, fn ->
      Render.compile_tex(tmp_path("model.tex"), engine: "definitely-not-a-real-tex-engine")
    end
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
