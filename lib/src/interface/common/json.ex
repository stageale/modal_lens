defmodule Src.Interface.Common.Json do
  @moduledoc """
  Converts internal Elixir values into deterministic JSON-compatible data.
  """

  alias Src.Core.Model
  alias Src.Core.Model.DDL
  alias Src.Core.Model.SDL

  @spec safe(term()) :: term()
  def safe(nil), do: nil
  def safe(value) when is_boolean(value), do: value
  def safe(value) when is_binary(value), do: value
  def safe(value) when is_number(value), do: value
  def safe(value) when is_atom(value), do: Atom.to_string(value)

  def safe(%SDL{} = model) do
    model
    |> Model.to_export_map()
    |> safe()
  end

  def safe(%DDL{} = model) do
    model
    |> Model.to_export_map()
    |> safe()
  end

  def safe(%MapSet{} = values) do
    values
    |> Enum.sort()
    |> Enum.map(&safe/1)
  end

  def safe(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> safe()
  end

  def safe(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> safe()
  end

  def safe(values) when is_list(values) do
    Enum.map(values, &safe/1)
  end

  def safe(values) when is_map(values) do
    Map.new(values, fn {key, value} ->
      {safe_key(key), safe(value)}
    end)
  end

  def safe(value), do: value

  defp safe_key(key) when is_binary(key), do: key
  defp safe_key(key) when is_atom(key), do: Atom.to_string(key)
  defp safe_key(key), do: to_string(key)
end
