defmodule Src.Err.ParseWarningTest do
  use ExUnit.Case, async: true

  alias Src.Err.ParseWarning

  test "stores a parser warning message" do
    warning = %ParseWarning{message: "No relation found"}
    assert warning.message == "No relation found"
  end
end
