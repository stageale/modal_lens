defmodule Src.Explanation.Visual.RenderTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.DDL
  alias Src.Core.Model.EDSTIT, as: EDSTITModel
  alias Src.Core.Model.Modality
  alias Src.Core.Model.SDL
  alias Src.Explanation.Visual.GraphViewCatalog
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

    assert content =~ "w0 [label=\"i1: go\", style=\"filled\""
    assert content =~ "fillcolor=\"#{Palette.hex(:cividis, 1.0)}\""
    assert content =~ "w0 -> w1 [color=\"#{Palette.hex(:cividis, 0.75)}\""
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

  test "materializes the seven ED-STIT filter combinations" do
    model = %EDSTITModel{
      cardinality: 2,
      actual_world: 1,
      agents: ["provider"],
      modalities: [
        Modality.new!("RBox", :settledness, [
          {0, 0},
          {1, 1},
          {0, 1},
          {1, 0}
        ]),
        Modality.new!("RStit", :stit, [{0, 1}], agent: "provider"),
        Modality.new!("ROught", :ought, [{1, 0}], agent: "provider"),
        Modality.new!("RBel", :belief, [{0, 1}], agent: "provider")
      ]
    }

    catalog = GraphViewCatalog.build(model)

    assert catalog.filter_keys == ["stit", "ought", "belief"]
    assert map_size(catalog.views) == 7

    view = GraphViewCatalog.fetch!(catalog, [:belief, :stit])

    assert view.id == "stit+belief"
    assert view.designated_world == 1

    assert Enum.map(view.relations, & &1.modality_id) ==
             ["settledness", "stit:provider", "belief:provider"]

    settledness = hd(view.relations)

    assert settledness.original_edges ==
             MapSet.new([{0, 0}, {1, 1}, {0, 1}, {1, 0}])

    assert Enum.map(
             settledness.edges,
             &{&1.source, &1.target, &1.direction}
           ) == [{0, 1, :undirected}]
  end

  test "writes selected ED-STIT relations without edge labels" do
    model = %EDSTITModel{
      kind: :countermodel,
      cardinality: 2,
      actual_world: 0,
      agents: ["provider"],
      modalities: [
        Modality.new!("RBox", :settledness, [{0, 1}]),
        Modality.new!("RBel", :belief, [{0, 1}], agent: "provider"),
        Modality.new!("ROught", :ought, [{1, 1}], agent: "provider")
      ],
      valuations: %{"p" => [true, false]}
    }

    path =
      Render.write_dot(model, tmp_path("ed_stit.dot"),
        atoms: ["p"],
        modalities: [:stit, :belief]
      )

    content = File.read!(path)

    assert content =~ "digraph EDSTITModel"
    assert content =~ "init -> w0"

    assert content =~
             "w0 -> w1 [color=\"#555555\", style=\"solid\", dir=\"forward\""

    assert content =~
             "w0 -> w1 [color=\"#1F77B4\", style=\"dotted\", dir=\"forward\""

    refute content =~ "w1 -> w1 ["
    refute content =~ "label=\"Belief(provider)\""

    assert content =~ "belief (provider): transitive"
    refute content =~ "ought (provider)"
  end

  test "highlights ED-STIT worlds and simplified relation edges" do
    model = %EDSTITModel{
      kind: :countermodel,
      cardinality: 2,
      actual_world: 0,
      agents: ["provider"],
      modalities: [
        Modality.new!(
          "RStit",
          :stit,
          [{0, 0}, {1, 1}, {0, 1}, {1, 0}],
          agent: "provider"
        )
      ],
      valuations: %{"corrective_action" => [true, false]}
    }

    highlight =
      Highlight.new(
        basis: :pattern,
        world_scores: %{0 => 1.0},
        edge_scores: %{{0, 1} => 1.0}
      )

    path =
      Render.write_dot(model, tmp_path("ed_stit_highlight.dot"),
        atoms: ["corrective_action"],
        highlight: highlight,
        palette: :cividis
      )

    content = File.read!(path)

    assert content =~ ~s(fillcolor="#{Palette.hex(:cividis, 1.0)}")
    assert content =~ ~s(w0 -> w1 [color="#1F77B4", style="solid", dir="none", penwidth=5.00])
  end

  test "an agent keeps its color when other groups are hidden" do
    model = %EDSTITModel{
      cardinality: 2,
      agents: ["a", "b"],
      modalities: [
        Modality.new!("RStit", :stit, [{0, 1}], agent: "a"),
        Modality.new!("RBel", :belief, [{0, 1}], agent: "b")
      ]
    }

    path =
      Render.write_dot(model, tmp_path("belief_only.dot"), modalities: [:belief])

    content = File.read!(path)

    assert content =~ "w0 -> w1 [color=\"#D62728\", style=\"dotted\""
    refute content =~ "stit (a)"
  end

  test "writes simplified ED-STIT TikZ edges and a property legend" do
    model = %EDSTITModel{
      kind: :countermodel,
      cardinality: 2,
      actual_world: 0,
      agents: ["provider"],
      modalities: [
        Modality.new!(
          "RStit",
          :stit,
          [{0, 0}, {1, 1}, {0, 1}, {1, 0}],
          agent: "provider"
        ),
        Modality.new!("RBel", :belief, [{0, 1}], agent: "provider")
      ],
      valuations: %{}
    }

    path = Render.write_tikz(model, tmp_path("ed_stit.tex"))
    content = File.read!(path)

    assert content =~
             "\\path[-,very thick,draw=agent0] (w0) edge (w1);"

    assert content =~ "reflexive, symmetric, transitive"

    assert content =~
             "\\path[->,dotted,draw=agent0] (w0) edge (w1);"

    refute content =~ "loop above"
  end

  test "reports missing external renderers" do
    assert_raise RuntimeError, Regex.compile!("LaTeX executable"), fn ->
      Render.compile_tex(
        tmp_path("model.tex"),
        engine: "definitely-not-a-real-engine"
      )
    end
  end

  defp tmp_path(filename) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_render_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    Path.join(dir, filename)
  end
end
