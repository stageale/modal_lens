defmodule Src.TPTP.IncludeTest do
  use ExUnit.Case, async: true

  alias Src.TPTP.Include

  test "includes all formulae by default" do
    include = Include.new("Axioms/SET001.ax")

    assert include.file == "Axioms/SET001.ax"
    assert include.selection == :all
    assert include.space == nil
  end

  test "preserves explicit selections and spaces" do
    include = Include.new("Axioms/SET001.ax", ["a1", "'a two'"], "space_1")

    assert include.selection == ["a1", "'a two'"]
    assert include.space == "space_1"
  end
end
