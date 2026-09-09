defmodule Src.TPTP.Detector do
  @moduledoc """
  Detects supported top-level TPTP constructs from raw source text.

  Detection is purely syntactic and does not parse or interpret
  the contained logical formula.
  """

  @typedoc """
  Supported top-level TPTP construct.
  """
  @type construct :: :thf | :include | :unknown

  @doc """
  Detects the top-level construct of a TPTP statement.
  """
  @spec detect(String.t()) :: construct()
  def detect(source) when is_binary(source) do
    source
    |> String.trim_leading()
    |> detect_prefix()
  end

  @spec detect_prefix(String.t()) :: construct()
  defp detect_prefix("thf(" <> _rest), do: :thf
  defp detect_prefix("include(" <> _rest), do: :include
  defp detect_prefix(_source), do: :unknown
end
