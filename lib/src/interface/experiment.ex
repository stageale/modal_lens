defmodule Src.Interface.Experiment do
  @moduledoc """
  Connects parsed Nitpick outputs with the active countermodel pipeline.

  The current experiment path deliberately does not perform axiom scoring or
  frame-axiom diagnosis. It parses one countermodel and prepares the data used
  for visualization, blocking, and later LLM explanations.
  """

  alias Src.Core.BlockingAxiom
  alias Src.Core.Model
  alias Src.Core.Parser

  @doc """
  Returns a compact summary of one Nitpick output.
  """
  def summary_file(path, opts \\ []) do
    model = parse_nitpick_file(path, opts)

    model
    |> Model.as_summary()
    |> Map.merge(%{
      file: path,
      worlds: Model.world_indices(model),
      warning_count: length(model.warnings)
    })
  end

  @doc """
  Parses one Nitpick output and prepares one countermodel entry.

  The returned map is intentionally small. It can later be enriched with:

    * GraphViz output paths
    * the Isabelle search theory
    * an LLM explanation
    * the next generated theory
  """
  def analyse_file(path, opts \\ []) do
    model = parse_nitpick_file(path, opts)

    blocking_axiom =
      BlockingAxiom.blocking_axiom(
        model,
        name: Keyword.get(opts, :blocking_name),
        include_atoms: Keyword.get(opts, :include_atoms, true)
      )

    %{
      file: path,
      model: model,
      worlds: Model.world_indices(model),
      blocking_axiom: blocking_axiom
    }
  end

  @doc """
  Parses a stored Isabelle/Nitpick output.
  """
  def parse_nitpick_file(path, opts \\ []) do
    Parser.parse_nitpick_file(path,
      relation: Keyword.get(opts, :relation, "R"),
      atoms:
        opts
        |> Keyword.get(:atoms, [])
        |> normalize_atoms(),
      auto_atoms: Keyword.get(opts, :auto_atoms, false)
    )
  end

  @doc """
  The old score-based ranking pipeline has been deprecated.

  This function remains temporarily so that older CLI code still compiles.
  It should be removed together with the old `rank` CLI command.
  """
  def rank_files(_paths, _opts \\ []) do
    raise ArgumentError,
          "axiom ranking is deprecated; use countermodel enumeration instead"
  end

  defp normalize_atoms(nil), do: []
  defp normalize_atoms(""), do: []
  defp normalize_atoms("-"), do: []

  defp normalize_atoms(atoms) when is_binary(atoms) do
    atoms
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_atoms(atoms) when is_list(atoms), do: atoms
end