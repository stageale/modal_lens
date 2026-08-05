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
    assert html =~ "assets/variant-1-model-1-graph.svg"
    assert html =~ "assets/variant-1-model-1-graph.tex"

    assert File.regular?(Path.join(root, "site/assets/variant-1-model-1-graph.svg"))
    assert File.regular?(Path.join(root, "site/assets/variant-1-model-1-graph.tex"))
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
