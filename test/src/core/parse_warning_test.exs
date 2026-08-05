defmodule Src.Core.ParseWarningTest do
  use ExUnit.Case, async: true

  alias Src.Core.ParseWarning

  test "requires and stores a parser warning message" do
    warning = %ParseWarning{message: "No relation found"}
    assert warning.message == "No relation found"

    assert_raise ArgumentError, fn ->
      struct!(ParseWarning, [])
    end
  end
end
