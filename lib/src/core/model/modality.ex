defmodule Src.Core.Model.Modality do
  @moduledoc """
  Represents one interpreted modality of a finite model.

  A modality records its semantic role independently of the concrete symbol
  used by the formal backend. For the currently supported Kripke-style
  semantics, its finite interpretation is represented by accessibility
  edges between worlds.

  Keeping the modal identity separate from its concrete interpretation
  allows ModalLens to extend this representation later to richer
  first-order and higher-order modal semantics without identifying a
  modality with a first-order relation symbol.
  """

  @typedoc "A zero-based world index."
  @type world_index :: non_neg_integer()

  @typedoc "A pair of accessible worlds in the finite interpretation."
  @type accessibility_edge ::
          {world_index(), world_index()}

  @typedoc """
  Semantic role of a modality in the current ED-STIТ embedding.
  """
  @type kind ::
          :settledness
          | :stit
          | :ought
          | :belief

  @typedoc "Identifier of an agent occurring in an indexed modality."
  @type agent :: String.t()

  @enforce_keys [
    :symbol,
    :kind
  ]

  defstruct [
    :symbol,
    :kind,
    :agent,
    accessibility: MapSet.new()
  ]

  @type t :: %__MODULE__{
          symbol: String.t(),
          kind: kind(),
          agent: agent() | nil,
          accessibility: MapSet.t(accessibility_edge())
        }

  @doc """
  Constructs an interpreted modality.

  Settledness is global. STIT, ought, and belief modalities are
  agent-indexed.
  """
  @spec new!(
          String.t(),
          kind(),
          Enumerable.t(),
          keyword()
        ) :: t()
  def new!(symbol, kind, accessibility, opts \\ [])

  def new!(symbol, kind, accessibility, opts)
      when kind in [:settledness, :stit, :ought, :belief] do
    %__MODULE__{
      symbol: normalize_symbol!(symbol),
      kind: kind,
      agent:
        normalize_agent!(
          kind,
          Keyword.get(opts, :agent)
        ),
      accessibility: MapSet.new(accessibility)
    }
  end

  def new!(_symbol, kind, _accessibility, _opts) do
    raise ArgumentError,
          "unsupported modality kind: #{inspect(kind)}"
  end

  @doc """
  Returns a stable semantic identifier.

  Examples:

      "settledness"
      "stit:provider"
      "ought:provider"
      "belief:provider"
  """
  @spec id(t()) :: String.t()
  def id(%__MODULE__{kind: :settledness}) do
    "settledness"
  end

  def id(%__MODULE__{kind: kind, agent: agent}) do
    "#{kind}:#{agent}"
  end

  @doc "Tests accessibility between two worlds."
  @spec accessible?(
          t(),
          world_index(),
          world_index()
        ) :: boolean()
  def accessible?(
        %__MODULE__{accessibility: accessibility},
        source,
        target
      ) do
    MapSet.member?(
      accessibility,
      {source, target}
    )
  end

  @doc "Number of accessibility pairs in the finite interpretation."
  @spec accessibility_count(t()) :: non_neg_integer()
  def accessibility_count(%__MODULE__{accessibility: accessibility}) do
    MapSet.size(accessibility)
  end

  @doc "Provides deterministic ordering of modalities."
  @spec sort_key(t()) ::
          {non_neg_integer(), String.t(), String.t()}
  def sort_key(%__MODULE__{} = modality) do
    {
      kind_order(modality.kind),
      modality.agent || "",
      modality.symbol
    }
  end

  defp normalize_symbol!(symbol)
       when is_binary(symbol) do
    case String.trim(symbol) do
      "" ->
        raise ArgumentError,
              "modality symbol must not be empty"

      normalized ->
        normalized
    end
  end

  defp normalize_symbol!(symbol) do
    raise ArgumentError,
          "modality symbol must be a string, got: #{inspect(symbol)}"
  end

  defp normalize_agent!(:settledness, nil),
    do: nil

  defp normalize_agent!(:settledness, agent) do
    raise ArgumentError,
          "settledness modality must not be agent-indexed, got: #{inspect(agent)}"
  end

  defp normalize_agent!(kind, agent)
       when kind in [:stit, :ought, :belief] and
              is_binary(agent) do
    case String.trim(agent) do
      "" ->
        raise ArgumentError,
              "#{kind} modality requires a non-empty agent identifier"

      normalized ->
        normalized
    end
  end

  defp normalize_agent!(kind, nil)
       when kind in [:stit, :ought, :belief] do
    raise ArgumentError,
          "#{kind} modality requires an agent identifier"
  end

  defp normalize_agent!(kind, agent)
       when kind in [:stit, :ought, :belief] do
    raise ArgumentError,
          "#{kind} modality requires a string agent identifier, got: #{inspect(agent)}"
  end

  defp kind_order(:settledness), do: 0
  defp kind_order(:stit), do: 1
  defp kind_order(:ought), do: 2
  defp kind_order(:belief), do: 3
end
