defmodule Src.Explanation.Visual.RenderTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.DDL
  alias Src.Core.Model.SDL
  alias Src.Explanation.Visual.Highlight
  alias Src.Explanation.Visual.Palette
  alias Src.Explanation.Visual.Render

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
        basis: :semantic,
        world_scores: %{0 => 1.0},
        edge_scores: %{{0, 1} => 0.75}
      )

    path = tmp_path("model.dot")

    written_path =
      Render.write_dot(model, path,
        atoms: ["go"],
        highlight: highlight,
        palette: :cividis
      )

    content = File.read!(written_path)

    assert content =~ ~s(w0 [label="i1: go", style="filled")
    assert content =~ ~s(fillcolor="#{Palette.hex(:cividis, 1.0)}")
    assert content =~ ~s(w0 -> w1 [color="#{Palette.hex(:cividis, 0.75)}")
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

  test "escapes LaTeX and writes TikZ" do
    assert Render.latex_escape("¬go_a&b") == "$\\neg$go\\_a\\&b"

    model = %SDL{
      kind: :countermodel,
      cardinality: 1,
      relation_name: "R",
      initial_world: 0,
      edges: MapSet.new([{0, 0}]),
      valuations: %{"go" => [true]}
    }

    path = Render.write_tikz(model, tmp_path("model.tex"), atoms: ["go"])
    content = File.read!(path)

    assert content =~ "\\documentclass"
    assert content =~ "\\node[world] (w0)"
    assert content =~ "i1: go"
    assert content =~ "\\path[->,loop above] (w0) edge (w0);"
  end

  test "reports missing external renderers" do
    assert_raise RuntimeError, ~r/LaTeX executable/, fn ->
      Render.compile_tex(tmp_path("model.tex"), engine: "definitely-not-a-real-engine")
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
