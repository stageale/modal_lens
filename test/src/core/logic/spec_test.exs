defmodule Src.Core.Logic.SpecTest do
  use ExUnit.Case, async: true

  alias Src.Core.Logic.Spec

  defmodule ModalLayer do
    defstruct [:operator]
  end

  defmodule QuantificationLayer do
    defstruct [:type]
  end

  test "creates an empty propositional specification" do
    assert {:ok, spec} = Spec.new("  SDL  ")

    assert spec.name == "SDL"
    assert spec.base == :propositional
    assert spec.layers == []
    assert spec.bridges == []
  end

  test "rejects empty and non-string names" do
    assert {:error, :invalid_name} = Spec.new("")
    assert {:error, :invalid_name} = Spec.new("   ")
    assert {:error, :invalid_name} = Spec.new(:sdl)
  end

  test "keeps semantic layers in composition order" do
    assert {:ok, spec} = Spec.new("Quantified modal logic")

    modal = %ModalLayer{operator: :box}
    quantification = %QuantificationLayer{type: :individual}

    assert {:ok, spec} =
             Spec.put_layer(spec, {:modal, :necessity}, modal)

    assert {:ok, spec} =
             Spec.put_layer(spec, {:quantification, :individual}, quantification)

    assert spec.layers == [
             {{:modal, :necessity}, modal},
             {{:quantification, :individual}, quantification}
           ]

    assert Spec.has_layer?(spec, {:modal, :necessity})
    assert {:ok, ^modal} = Spec.fetch_layer(spec, {:modal, :necessity})
    assert :error = Spec.fetch_layer(spec, {:modal, :knowledge})
  end

  test "does not silently replace duplicate layers" do
    assert {:ok, spec} = Spec.new("Multimodal logic")
    layer = %ModalLayer{operator: :box}

    assert {:ok, spec} =
             Spec.put_layer(spec, {:modal, :knowledge}, layer)

    assert {:error, {:duplicate_layer, {:modal, :knowledge}}} =
             Spec.put_layer(
               spec,
               {:modal, :knowledge},
               %ModalLayer{operator: :other}
             )
  end

  test "rejects invalid keys and non-struct layer values" do
    assert {:ok, spec} = Spec.new("Example")

    assert {:error, :invalid_layer_key} =
             Spec.put_layer(spec, {"modal", :box}, %ModalLayer{})

    assert {:error, :invalid_layer} =
             Spec.put_layer(spec, {:modal, :box}, %{operator: :box})
  end
end
