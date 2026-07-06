defmodule Src.Interface.Experiment do
  alias Src.Core.Parser
  alias Src.HardcodedRefinement.FrameAnalysis
  alias Src.HardcodedRefinement.AxiomScoring
  alias Src.VisualExplanations.AxiomExplanation

  def summary_file(path, opts \\ []) do
    path
    |> analyse_file(opts)
    |> build_summary()
  end

  defp suggestion_summary(suggestion) do
    %{
      axiom: suggestion.axiom,
      score: suggestion.score,
      violations: suggestion.violations,
      support: suggestion.support,
      density: suggestion.density
    }
  end

  defp build_summary(entry) do
    best =
      entry.suggestions
      |> Enum.sort_by(fn suggestion -> suggestion.score end, :desc)
      |> List.first()

    %{
      source: entry.model.source,
      file: entry.file,
      kind: entry.model.kind,
      cardinality: entry.model.cardinality,
      relation: entry.model.relation_name,
      initial_world: "i#{entry.model.initial_world + 1}",
      edge_count: MapSet.size(entry.model.edges),
      atoms: entry.model.valuations |> Map.keys() |> Enum.sort(),
      warning_count: length(entry.model.warnings),
      warnings: Enum.map(entry.model.warnings, &warning_message/1),
      worlds: entry.worlds,
      analysis: entry.analysis,
      suggestion_count: length(entry.suggestions),
      explanation_count: length(entry.explanations),
      best_axiom: if(best, do: best.axiom, else: nil),
      best_score: if(best, do: best.score, else: 0.0),
      suggestions: Enum.map(entry.suggestions, &suggestion_summary/1)
    }
  end

  def analyse_file(path, opts \\ []) do
    model = parse_nitpick_file(path, opts)
    worlds = FrameAnalysis.worlds_for_model(model)
    analysis = FrameAnalysis.analysis_from_model(model, worlds)

    suggestions =
      AxiomScoring.ranked_suggestions(analysis, worlds, model.edges)

    explanations =
      AxiomExplanation.explain_all(analysis)

    %{
      file: path,
      model: model,
      worlds: worlds,
      analysis: analysis,
      suggestions: suggestions,
      explanations: explanations
    }
  end

  defp parse_nitpick_file(path, opts) do
    Parser.parse_nitpick_file(path,
      relation: Keyword.get(opts, :relation, "R"),
      atoms: opts |> Keyword.get(:atoms, []) |> normalize_atoms(),
      auto_atoms: Keyword.get(opts, :auto_atoms, false)
    )
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

  defp warning_message(warning) when is_binary(warning), do: warning
  defp warning_message(%{message: message}), do: message
  defp warning_message(warning), do: inspect(warning)

  def rank_files(paths, opts \\ []) do
    paths
    |> List.wrap()
    |> Enum.map(&analyse_file(&1, opts))
    |> rank_results(opts)
  end


  defp suggestion_rows(entry) do
    Enum.map(entry.suggestions, fn suggestion ->
      %{
        file: entry.file,
        axiom: suggestion.axiom,
        score: suggestion.score,
        violations: suggestion.violations,
        support: suggestion.support,
        density: suggestion.density
      }
    end)
  end

  defp aggregate_axiom_group({axiom, rows}) do
    %{
      axiom: axiom,
      score: sum(rows, :score),
      violations: sum(rows, :violations),
      support: sum(rows, :support),
      affected_models: Enum.count(rows, fn row -> row.violations > 0 end),
      models: Enum.map(rows, fn row ->
        %{
          file: row.file,
          score: row.score,
          violations: row.violations,
          support: row.support,
          density: row.density
        }
      end)
    }
  end

  defp sum(rows, key) do
    rows
    |> Enum.map(fn row -> Map.get(row, key, 0) end)
    |> Enum.sum()
  end

  defp maybe_limit(rows, nil), do: rows

  defp maybe_limit(rows, limit) when is_integer(limit) and limit > 0 do
    Enum.take(rows, limit)
  end

  defp maybe_limit(rows, _limit), do: rows

  defp model_rank_summary(entry) do
    best =
      entry.suggestions
      |> Enum.sort_by(fn suggestion -> suggestion.score end, :desc)
      |> List.first()

    %{
      file: entry.file,
      kind: entry.model.kind,
      cardinality: entry.model.cardinality,
      edge_count: MapSet.size(entry.model.edges),
      warning_count: length(entry.model.warnings),
      best_axiom: if(best, do: best.axiom, else: nil),
      best_score: if(best, do: best.score, else: 0.0),
      suggestions: Enum.map(entry.suggestions, &suggestion_summary/1)
    }
  end

  def rank_results(entries, opts \\ []) when is_list(entries) do
    limit = Keyword.get(opts, :limit)

    ranked_axioms =
      entries
      |> Enum.flat_map(&suggestion_rows/1)
      |> Enum.group_by(fn row -> row.axiom end)
      |> Enum.map(&aggregate_axiom_group/1)
      |> Enum.sort_by(
        fn row ->
          {row.score, row.violations, row.affected_models, row.support}
        end,
        :desc
      )
      |> maybe_limit(limit)

    %{
      input_count: length(entries),
      inputs: Enum.map(entries, fn entry -> entry.file end),
      ranked_axioms: ranked_axioms,
      models: Enum.map(entries, &model_rank_summary/1)
    }
  end
end
