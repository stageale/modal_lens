defmodule Src.Interface.Ui.PageTest do
  use ExUnit.Case, async: true

  alias Src.Execution.Options
  alias Src.Execution.Run
  alias Src.Interface.Ui.Page
  alias Src.Interface.Ui.Session

  test "writes HTML and copies model graph assets" do
    root = tmp_dir()
    graph_file = Path.join(root, "graph.svg")
    tikz_file = Path.join(root, "graph.tex")
    page_file = Path.join(root, "site/index.html")

    File.write!(graph_file, "<svg></svg>")
    File.write!(tikz_file, "\\begin{tikzpicture}\\end{tikzpicture}")

    assert {:ok, options} = Options.new(verbalize?: false)
    assert {:ok, session} = Session.new("Example.thy")
    assert {:ok, run} = Run.new("variant-1", Path.join(root, "run"))

    result = %{
      status: :max_models_reached,
      model_count: 1,
      graph_analysis: %{cluster_count: 1},
      clusters: [
        %{
          cluster_id: 0,
          model_count: 1,
          model_fraction: 1.0,
          characteristic_patterns: [],
          models: [
            %{
              iteration: 1,
              model_summary: %{cardinality: 1},
              graph_svg_file: graph_file,
              graph_tikz_file: tikz_file,
              graph_pdf_file: nil,
              blocking_axiom: "not model"
            }
          ]
        }
      ],
      cluster_verbs: []
    }

    session = Session.put_variant(session, options, run, result)
    assert {:ok, ^page_file} = Page.write(session, page_file)

    html = File.read!(page_file)
    assert html =~ "<pre id=\"options\"></pre>"
    assert html =~ "overflow-wrap: anywhere"
    assert html =~ ~r/assets\/variant-1-model-1-[a-f0-9]{12}-graph.svg/
    assert html =~ ~r/assets\/variant-1-model-1-[a-f0-9]{12}-graph.tex/

    assert [copied_svg] = Path.wildcard(Path.join(root, "site/assets/*-graph.svg"))
    assert [copied_tex] = Path.wildcard(Path.join(root, "site/assets/*-graph.tex"))
    assert File.read!(copied_svg) == File.read!(graph_file)
    assert File.read!(copied_tex) == File.read!(tikz_file)
  end

  test "keeps models with the same iteration from different cardinalities distinct" do
    root = tmp_dir()
    models = Enum.map([2, 3], fn cardinality ->
      dir = Path.join(root, "cardinality_#{cardinality}/iteration_001")
      File.mkdir_p!(dir)
      svg = Path.join(dir, "model.svg")
      tex = Path.join(dir, "model.tex")
      File.write!(svg, "<svg id=\"card#{cardinality}\"></svg>")
      File.write!(tex, "cardinality #{cardinality}")
      %{
        iteration: 1, model_summary: %{cardinality: cardinality},
        graph_svg_file: svg, graph_tikz_file: tex,
        graph_views: %{
          filter_keys: ["belief"], default_view: "belief",
          views: %{"belief" => %{modalities: ["belief"], graph_svg_file: svg, graph_tikz_file: tex}}
        }
      }
    end)
    assert {:ok, options} = Options.new(verbalize?: false)
    assert {:ok, session} = Session.new("Example.thy")
    assert {:ok, run} = Run.new("variant", Path.join(root, "run"))
    result = %{model_count: 2, clusters: [%{cluster_id: 0, models: models}]}
    session = Session.put_variant(session, options, run, result)
    html_dir = Path.join(root, "site")
    assert {:ok, page} = Page.write(session, Path.join(html_dir, "index.html"))
    [_, suffix] = String.split(File.read!(page), "const variants = ", parts: 2)
    [encoded | _] = String.split(suffix, ";\n", parts: 2)
    [variant] = Jason.decode!(encoded)
    [first, second] = hd(variant["result"]["clusters"])["models"]

    refute first["graph_svg_file"] == second["graph_svg_file"]
    refute first["graph_tikz_file"] == second["graph_tikz_file"]
    for {model, cardinality} <- [{first, 2}, {second, 3}] do
      assert File.read!(Path.join(html_dir, model["graph_svg_file"])) ==
               "<svg id=\"card#{cardinality}\"></svg>"
      assert File.read!(Path.join(html_dir, model["graph_tikz_file"])) ==
               "cardinality #{cardinality}"
      assert model["graph_views"]["views"]["belief"]["graph_svg_file"] == model["graph_svg_file"]
    end
  end

  test "escapes closing script sequences in encoded data" do
    html = Page.render([%{value: "</script><script>alert(1)</script>"}])
    refute html =~ "</script><script>alert(1)"
    assert html =~ "<\\/script>"
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ui_page_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
