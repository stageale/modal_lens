defmodule Src.Core.Logic.Spec do
  @moduledoc """
  Describes a logic assembled from a propositional base,
  independent semantic layers, and explicit bridge principles.

  A specification contains no concrete model and no Isabelle-specific names.
  """

  @type base :: :propositional

  @type layer_key :: atom() | {atom(), term()}

  @type layer :: struct()
  @type layer_entry :: {layer_key(), layer()}
  @type bridge :: struct()

  @type t :: %__MODULE__{
    name: String.t(),
    base: base(),
    layers: [layer_entry()],
    bridges: [bridge()]
  }

  @enforce_keys [:name]

  defstruct name: nil,
            base: :propositional,
            layers: [],
            bridges: []

  @doc """
  Creates an empty propositional logic specification.
  """
  @spec new(term()) :: {:ok, t()} | {:error, :invalid_name}
  def new(name) when is_binary(name) do
    case String.trim(name) do
      "" -> {:error, :invalid_name}
      normalized -> {:ok, %__MODULE__{name: normalized}}
    end
  end

  @doc """
  Adds a semantic layer without replacing existing layers.
  """
  @spec put_layer(t(), term(), term()) :: {:ok, t()}
                                        | {:error, :invalid_layer_key}
                                        | {:error, :invalid_layer}
                                        | {:error, {:duplicate_layer, term()}}
  def put_layer(%__MODULE__{} = spec, key, layer) do
    cond do
      not valid_layer_key?(key) -> {:error, :invalid_layer_key}
      not is_struct(layer) -> {:error, :invalid_layer}
      has_layer?(spec, key) -> {:error, {:duplicate_layer, key}}
      true -> {:ok, %{spec | layers: spec.layers ++ [{key, layer}]}}
    end
  end

  @doc """
  Retrieves a layer by its unique key.
  """
  @spec fetch_layer(t(), layer_key()) :: {:ok, layer()} | :error
  def fetch_layer(%__MODULE__{} = spec, key) do
    case List.keyfind(spec.layers, key, 0) do
      {_key, layer} -> {:ok, layer}
      nil -> :error
    end
  end

  @doc """
  Checks whether a layer is already present.
  """
  @spec has_layer?(t(), layer_key()) :: boolean()
  def has_layer?(%__MODULE__{} = spec, key) do
    Enum.any?(spec.layers, fn {existing_key, _layer} -> existing_key == key end)
  end

  defp valid_layer_key?(key) when is_atom(key), do: true

  defp valid_layer_key?({family, identifier}) when is_atom(family) and (is_atom(identifier) or is_binary(identifier)), do: true

  defp valid_layer_key?(_key), do: false
end
