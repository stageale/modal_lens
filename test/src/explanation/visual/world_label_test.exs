defmodule Src.Explanation.Visual.WorldLabelTest do
  use ExUnit.Case, async: true

  alias Src.Core.Model.SDL
  alias Src.Explanation.Visual.WorldLabel

  test "keeps short labels on one line" do
    model = %SDL{
      cardinality: 1,
      initial_world: 0,
      valuations: %{"go" => [true]}
    }

    assert WorldLabel.lines(model, 0, ["go"]) == ["i1: go"]
  end

  test "wraps long valuation labels without changing the logical label" do
    model = %SDL{
      cardinality: 1,
      initial_world: 0,
      valuations: %{
        "designation_suspended" => [true],
        "inform_providers" => [false]
      }
    }

    assert WorldLabel.lines(
             model,
             0,
             ["designation_suspended", "inform_providers"]
           ) == [
             "i1",
             "designation_suspended",
             "¬inform_providers"
           ]
  end
end
