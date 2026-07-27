defmodule Src.Explanation.Visual.Palette do
  @moduledoc """
  Maps normalized heatmap scores to renderer-independent RGB colors.
  """

  @type palette ::
          :cividis
          | :viridis
          | :plasma
          | :magma
          | :turbo

  @type score :: float()
  @type rgb :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @palettes %{
    cividis: [
      {0, 34, 78},
      {33, 59, 110},
      {76, 85, 108},
      {108, 110, 114},
      {142, 137, 120},
      {177, 165, 112},
      {217, 197, 92},
      {254, 232, 56}
    ],
    viridis: [
      {68, 1, 84},
      {70, 50, 126},
      {54, 92, 141},
      {39, 127, 142},
      {31, 161, 135},
      {74, 193, 109},
      {160, 218, 57},
      {253, 231, 37}
    ],
    plasma: [
      {13, 8, 135},
      {83, 2, 163},
      {139, 10, 165},
      {184, 50, 137},
      {219, 92, 104},
      {244, 136, 73},
      {254, 189, 42},
      {240, 249, 33}
    ],
    magma: [
      {0, 0, 4},
      {34, 17, 80},
      {95, 24, 127},
      {152, 45, 128},
      {211, 67, 110},
      {248, 118, 92},
      {254, 187, 129},
      {252, 253, 191}
    ],
    turbo: [
      {48, 18, 59},
      {71, 118, 238},
      {27, 208, 213},
      {97, 252, 108},
      {210, 233, 53},
      {254, 155, 45},
      {218, 57, 7},
      {122, 4, 3}
    ]
  }

  @intervals 7

  @spec color(palette(), number()) :: rgb()
  def color(palette, score) when is_number(score) and score >= 0.0 and score <= 1.0 do
    palette
    |> stops()
    |> interpolate(score)
  end

  def color(_palette, score) do
    raise ArgumentError, "palette score must be between 0.0 and 1.0, got: #{inspect(score)}"
  end

  @spec hex(palette(), number()) :: String.t()
  def hex(palette, score) do
    {red, green, blue} = color(palette, score)

    "#" <>
      hex_channel(red) <>
      hex_channel(green) <>
      hex_channel(blue)
  end

  def hex_channel(channel) do
    channel
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
    |> String.upcase()
  end

  @spec normalize_score(number(), number(), boolean()) :: float()
  def normalize_score(score, scale \\ 1.0, negative \\ false)

  def normalize_score(score, scale, negative) when is_number(score) and is_number(scale) and scale > 0 and is_boolean(negative) do
    if negative do
      normalize_signed_score(score, scale)
    else
      normalize_positive_score(score, scale)
    end
  end

  def normalize_score(score, scale, negative) do
    raise ArgumentError,
          "score and scale must be numerics, scale positive and negative a boolean got: #{inspect(score)}, #{inspect(scale)}, #{inspect(negative)}"
  end

  defp normalize_positive_score(score, scale) when score >= 0 do
    score / (score + scale)
  end

  defp normalize_positive_score(score, _scale) do
    raise ArgumentError,
          "negative score #{inspect(score)} requires enabled_negatives: true"
  end

  defp normalize_signed_score(score, scale) do
    0.5 + 0.5 * score / (abs(score) + scale)
  end

  defp interpolate(colors, score) do
    position = score * @intervals

    left_index =
      position
      |> :math.floor()
      |> trunc()

    right_index = min(left_index + 1, @intervals)
    factor = position - left_index

    left_color = Enum.at(colors, left_index)
    right_color = Enum.at(colors, right_index)

    interpolate_rgb(left_color, right_color, factor)
  end

  defp stops(palette) do
    case Map.fetch(@palettes, palette) do
      {:ok, colors} -> colors
      :error ->
        raise ArgumentError, "unsupported palette: #{inspect(palette)}"
    end
  end

  defp interpolate_rgb({left_red, left_green, left_blue},
                       {right_red, right_green, right_blue},
                       factor) do
    {
      interpolate_channel(left_red, right_red, factor),
      interpolate_channel(left_green, right_green, factor),
      interpolate_channel(left_blue, right_blue, factor)
    }
  end

  defp interpolate_channel(left, right, factor) do
    left
    |> Kernel.+((right - left) * factor)
    |> round()
    |> max(0)
    |> min(255)
  end
end
