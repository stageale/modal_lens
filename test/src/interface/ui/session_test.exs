defmodule Src.Interface.Ui.SessionTest do
  use ExUnit.Case, async: true

  alias Src.Execution.Options
  alias Src.Execution.Run
  alias Src.Interface.Ui.Session

  test "creates a session and stores or replaces variants" do
    assert {:ok, session} = Session.new("examples/input/E.thy")
    assert session.theory_path == Path.expand("examples/input/E.thy")
    assert session.variants == []

    assert {:ok, options} = Options.new()
    assert {:ok, run} = Run.new("variant-1", "/tmp/variant-1")

    session =
      session
      |> Session.put_variant(options, run, %{status: :first})
      |> Session.put_variant(options, run, %{status: :replacement})

    assert [variant] = session.variants
    assert variant.options == options
    assert variant.run == run
    assert variant.result.status == :replacement
  end

  test "keeps different option variants" do
    assert {:ok, session} = Session.new("E.thy")
    assert {:ok, first} = Options.new(palette: :turbo)
    assert {:ok, second} = Options.new(palette: :magma)
    assert {:ok, run1} = Run.new("one", "/tmp/one")
    assert {:ok, run2} = Run.new("two", "/tmp/two")

    session =
      session
      |> Session.put_variant(first, run1, %{status: :one})
      |> Session.put_variant(second, run2, %{status: :two})

    assert length(session.variants) == 2
  end

  test "rejects invalid theory paths" do
    assert {:error, :invalid_theory_path} = Session.new("")
    assert {:error, :invalid_theory_path} = Session.new(nil)
  end
end
