defmodule Src.Interface.Experiment do
  @moduledoc """
  Provides the file-based workflow for stored Isabelle/Nitpick output.

  Theory execution and countermodel enumeration are handled by
  `Src.ModelEnumeration`. This module only parses existing Nitpick output and
  derives summaries or blocking axioms from the parsed model.
  """

  alias Src.Core.BlockingAxiom
  alias Src.Core.Model
  alias Src.Core.Parser


  @doc """
  Parses one previously stored Nitpick output and prepares its basic data.

  This keeps the older file-based workflow usable without invoking Isabelle.
  """
  def analyse_file(path, opts \\ []) do
    model = parse_nitpick_file(path, opts)

    blocking_axiom =
      BlockingAxiom.blocking_axiom(
        model,
        name: Keyword.get(opts, :blocking_name),
        include_atoms: Keyword.get(opts, :include_atoms, true),
        include_initial: Keyword.get(opts, :include_initial, false),
        initial_world_constant: Keyword.get(opts, :initial_world_constant, "actual_world")
      )

    %{
      status: :parsed_countermodel,
      file: Path.expand(path),
      model: model,
      model_summary: Model.as_summary(model),
      worlds: Model.world_indices(model),
      warnings: Model.warning_messages(model),
      blocking_axiom: blocking_axiom,
      highlight: Keyword.get(opts, :highlight),
      llm_explanation: nil,
      llm_metadata: nil
    }
  end

  @doc """
  Returns a compact summary of one stored Nitpick output.
  """
  def summary_file(path, opts \\ []) do
    model = parse_nitpick_file(path, opts)

    model
    |> Model.as_summary()
    |> Map.merge(%{
      file: Path.expand(path),
      worlds: Model.world_indices(model),
      warning_count: length(model.warnings)
    })
  end

  @doc """
  Parses a stored Isabelle/Nitpick output.
  """
  def parse_nitpick_file(path, opts \\ []) do
    Parser.parse_nitpick_file(path,
      model_logic: Keyword.get(opts, :model_logic, :sdl),
      relation: Keyword.get(opts, :relation, "R"),
      atoms: Keyword.get(opts, :atoms, []),
      auto_atoms: Keyword.get(opts, :auto_atoms, false)
    )
  end
end
