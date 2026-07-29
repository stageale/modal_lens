defmodule Src.Interface.Ui.SessionTest do
  use ExUnit.Case, async: true

  alias Src.Interface.Common.Run
  alias Src.Interface.Ui.{Options, Session}

  test "stores and replaces variants" do
    {:ok, options} = Options.new()
    {:ok, session} = Session.new("examples/input/E.thy", options)
    {:ok, run} = Run.new("variant-1", "/tmp/variant-1")

    session =
      session
      |> Session.put_variant(options, run, %{status: :first})
      |> Session.put_variant(options, run, %{status: :replacement})

    assert length(session.variants) == 1
    assert {:ok, variant} = Session.current_variant(session)
    assert variant.result.status == :replacement
  end

  test "changes the active options" do
    {:ok, options} = Options.new()
    {:ok, session} = Session.new("examples/input/E.thy", options)

    assert {:ok, session} =
             Session.select(session, palette: :magma)

    assert session.options.palette == :magma
  end
end
