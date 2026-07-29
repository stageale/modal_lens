defmodule Src.Explanation.Visual.PaletteTest do
  use ExUnit.Case, async: true

  alias Src.Explanation.Visual.Palette

  describe "normalize_score/3" do
    test "normalizes non-negative scores" do
      assert Palette.normalize_score(0, 1.0) == 0.0
      assert Palette.normalize_score(1, 1.0) == 0.5
      assert_in_delta Palette.normalize_score(9, 1.0), 0.9, 0.0001
    end

    test "normalizes signed scores" do
      assert Palette.normalize_score(-1, 1.0, true) == 0.25
      assert Palette.normalize_score(0, 1.0, true) == 0.5
      assert Palette.normalize_score(1, 1.0, true) == 0.75
    end

    test "rejects negative scores by default" do
      assert_raise ArgumentError, fn ->
        Palette.normalize_score(-1, 1.0)
      end
    end

    test "rejects a non-boolean negative option" do
      assert_raise ArgumentError, fn ->
        Palette.normalize_score(1, 1.0, :invalid)
      end
    end

    test "rejects a non-positive scale" do
      assert_raise ArgumentError, fn ->
        Palette.normalize_score(1, 0)
      end
    end

    test "rejects a non-boolean enable_negatives option" do
      assert_raise ArgumentError, fn ->
        Palette.normalize_score(1, 1.0, enable_negatives: :yes)
      end
    end
  end

  describe "color/2" do
    test "returns the first palette color for zero" do
      assert Palette.color(:viridis, 0.0) == {68, 1, 84}
      assert Palette.color(:cividis, 0.0) == {0, 34, 78}
    end

    test "returns the final palette color for one" do
      assert Palette.color(:viridis, 1.0) == {253, 231, 37}
      assert Palette.color(:magma, 1.0) == {252, 253, 191}
    end

    test "interpolates between neighboring stops" do
      assert Palette.color(:viridis, 0.5) == {35, 144, 139}
    end

    test "rejects values outside the normalized interval" do
      assert_raise ArgumentError, fn ->
        Palette.color(:plasma, -1.0)
      end

      assert_raise ArgumentError, fn ->
        Palette.color(:plasma, 2.0)
      end
    end

    test "supports all configured palettes" do
      for palette <- [:cividis, :viridis, :plasma, :magma, :turbo] do
        assert {red, green, blue} = Palette.color(palette, 0.5)

        assert red in 0..255
        assert green in 0..255
        assert blue in 0..255
      end
    end

    test "rejects unsupported palettes" do
      assert_raise ArgumentError, fn ->
        Palette.color(:rainbow, 0.5)
      end
    end
  end

  describe "hex/2" do
    test "returns an uppercase GraphViz-compatible hex color" do
      assert Palette.hex(:viridis, 0.0) == "#440154"
      assert Palette.hex(:viridis, 0.5) == "#23908B"
      assert Palette.hex(:viridis, 1.0) == "#FDE725"
    end
  end
end
