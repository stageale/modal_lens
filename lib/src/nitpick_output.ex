defmodule Src.NitpickOutput do
  @moduledoc """
  Provides file-based operations for existing Isabelle/Nitpick output.

  The module parses stored Nitpick results and derives analyses, summaries,
  or blocking axioms from the resulting finite model.

  Live Isabelle execution and repeated model enumeration are handled by
  `Src.Enumeration`.
  """

  alias Src.Core.BlockingAxiom
  alias Src.Core.Model
  alias Src.Core.Parser

  @doc """
  Parses one previously stored Nitpick output and prepares its basic data.

  This keeps the older file-based workflow usable without invoking Isabelle.
  """
  @spec analyse_file(Path.t()) :: map()
  @spec analyse_file(Path.t(), keyword()) :: map()
  def analyse_file(path, opts \\ []) do
    model = parse_nitpick_file(path, opts)

    blocking_axiom =
      BlockingAxiom.blocking_axiom(
        model,
        name: Keyword.get(opts, :blocking_name),
        include_atoms: Keyword.get(opts, :include_atoms, true),
        include_designated_world: Keyword.get(opts, :include_designated_world, false),
        designated_world_constant:
          Keyword.get(
            opts,
            :designated_world_constant,
            Model.designated_world_constant(model)
          )
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
  @spec summary_file(Path.t()) :: map()
  @spec summary_file(Path.t(), keyword()) :: map()
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
  @spec parse_nitpick_file(Path.t()) :: Model.model()
  @spec parse_nitpick_file(Path.t(), keyword()) :: Model.model()
  def parse_nitpick_file(path, opts \\ []) do
    Parser.parse_nitpick_file(path,
      model_logic: Keyword.get(opts, :model_logic, :sdl),
      relation: Keyword.get(opts, :relation, "R"),
      atoms: Keyword.get(opts, :atoms, []),
      auto_atoms: Keyword.get(opts, :auto_atoms, true)
    )
  end
end
