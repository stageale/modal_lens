defmodule Src.Explanation.Visual.WorldLabel do
  @moduledoc """
  Presentation helpers for compact, readable world labels.

  Logical model labels remain unchanged. This module only introduces line
  breaks for renderers when a valuation label would otherwise become wider
  than the world node.
  """

  alias Src.Core.Model

  @default_max_chars 22

  @doc "Returns one or more display lines for a world label."
  @spec lines(Model.model(), non_neg_integer(), [String.t()] | nil, keyword()) :: [String.t()]
  def lines(model, world, atoms \\ nil, opts \\ []) do
    max_chars = Keyword.get(opts, :max_chars, @default_max_chars)
    label = Model.label_for_world(model, world, atoms)

    case String.split(label, ": ", parts: 2) do
      [_world_name] ->
        [label]

      [world_name, valuations] ->
        if String.length(label) <= max_chars do
          [label]
        else
          valuation_lines =
            valuations
            |> String.split(", ", trim: true)
            |> pack(max_chars)

          [world_name | valuation_lines]
        end
    end
  end

  defp pack(items, max_chars) do
    {lines, current} =
      Enum.reduce(items, {[], []}, fn item, {lines, current} ->
        candidate = Enum.join(current ++ [item], ", ")

        cond do
          current == [] ->
            {lines, [item]}

          String.length(candidate) <= max_chars ->
            {lines, current ++ [item]}

          true ->
            {lines ++ [Enum.join(current, ", ")], [item]}
        end
      end)

    case current do
      [] -> lines
      _ -> lines ++ [Enum.join(current, ", ")]
    end
  end
end
