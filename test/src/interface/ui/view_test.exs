defmodule Src.Interface.Ui.ViewTest do
  use ExUnit.Case, async: true

  alias Src.Interface.Common.Run
  alias Src.Interface.Ui.{Options, Session, View}

  test "projects the current result without internal model data" do
    {:ok, options} = Options.new(verbalize?: false)
    {:ok, session} = Session.new("Example.thy", options)
    {:ok, run} = Run.new("variant-1", "/tmp/variant-1")

    result = %{
      status: :completed,
      theory_name: "Example",
      report_file: "/tmp/report.json",
      graph_analysis: %{cluster_count: 1},
      model: :internal
    }

    session = Session.put_variant(session, options, run, result)
    view = View.current(session)

    assert view.status == :ready
    assert view.result.report_file == "/tmp/report.json"
    refute Map.has_key?(view.result, :model)
  end
end
