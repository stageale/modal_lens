defmodule Src.Interface.Ui.OptionsTest do
  use ExUnit.Case, async: true

  alias Src.Interface.Ui.Options

  test "creates and updates UI options" do
    assert {:ok, options} = Options.new()
    assert options.graph_format == :svg
    assert options.palette == :turbo

    assert {:ok, options} =
             Options.update(options,
               graph_format: :png,
               verbalize?: false
             )

    params = Options.to_run_params(options)

    assert params.graph_format == "png"
    assert params.auto_atoms
    refute params.verbalize?
  end

  test "rejects unsupported values" do
    assert {:error, {:invalid_palette, :unknown}} =
             Options.new(palette: :unknown)
  end
end
