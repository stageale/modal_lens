defmodule Src.Interface.Ui.PageTest do
  use ExUnit.Case, async: true

  alias Src.Interface.Common.Run
  alias Src.Interface.Ui.{Options, Page, Session}

  test "writes the HTML page and copies the graph asset" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ui_page_#{System.unique_integer([:positive])}"
      )

    graph_file = Path.join(root, "graph.svg")
    page_file = Path.join(root, "index.html")

    File.mkdir_p!(root)
    File.write!(graph_file, "<svg></svg>")

    {:ok, options} = Options.new(verbalize?: false)
    {:ok, session} = Session.new("Example.thy", options)
    {:ok, run} = Run.new("variant-1", Path.join(root, "run"))

    session =
      Session.put_variant(session, options, run, %{
        graph_image_file: graph_file,
        blocking_axiom: "¬ p",
        llm_explanation: nil
      })

    assert {:ok, ^page_file} = Page.write(session, page_file)

    html = File.read!(page_file)

    assert html =~ "<pre id=\"options\"></pre>"
    assert html =~ "overflow-wrap: anywhere"
    assert html =~ "assets/variant-1-graph.svg"

    assert File.regular?(
             Path.join(root, "assets/variant-1-graph.svg")
           )
  end
end
