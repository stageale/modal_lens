defmodule Src.TPTP.IsolationTest do
  use ExUnit.Case, async: true

  test "TPTP subsystem does not depend on Src.Core" do
    offenders =
      "lib/src/tptp/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.contains?("Src.Core")
      end)

    assert offenders == []
  end
end
