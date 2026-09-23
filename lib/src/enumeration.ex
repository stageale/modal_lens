defmodule Src.Enumeration do
  @moduledoc """
  The module controls repeated model enumeration.

  Individual Isabelle/Nitpick iterations are executed by
  `Src.Enumeration.Iteration`, while generated search theories are handled
  by `Src.Enumeration.SearchTheory`.
  """

  alias Src.Enumeration.Iteration
  alias Src.Enumeration.SearchTheory

  @default_input_theory "../data/Input.thy"

  @doc """
  Enumerates models using the bundled default input theory.

  See `enumerate/2` for the supported options.
  """
  @spec enumerate(keyword()) :: {:ok, map()} | {:error, term()}
  def enumerate(opts) when is_list(opts) do
    enumerate(default_input_theory_path(), opts)
  end

  @doc """
  Enumerates distinct countermodels for one fixed base theory.

  The base theory, selected axiom option, and investigated query remain fixed.
  For every discovered countermodel, a model-specific blocking axiom is added
  to a newly generated search theory.

  Options:

    * `:mode`
      Required enumeration mode. Supported values are `:countermodels`,
      `:satisfying_models`, and `:consistency_check`.

    * `:max_models`
      Maximum number of countermodels. Defaults to `5`.

    * `:output_dir`
      Root directory of the complete enumeration.

  All remaining options are forwarded to `run_iteration/2`.
  """
  @spec enumerate(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def enumerate(base_theory_path, opts) when is_binary(base_theory_path) and is_list(opts) do
    base_theory_path = Path.expand(base_theory_path)

    mode = Keyword.fetch!(opts, :mode)
    cardinalities = Keyword.get(opts, :cardinalities, [2])

    max_models =
      case mode do
        :consistency_check -> 1
        _ -> Keyword.get(opts, :max_models, 10)
      end

    output_root =
      opts
      |> Keyword.get(
        :output_dir,
        default_enumeration_output_dir(base_theory_path)
      )
      |> Path.expand()

    with :ok <- validate_base_theory(base_theory_path),
         :ok <- validate_cardinalities(cardinalities),
         :ok <- validate_max_models(max_models),
         :ok <- ensure_output_dir(output_root) do
      enumerate_cardinalities(
        base_theory_path,
        cardinalities,
        max_models,
        output_root,
        opts
      )
    end
  end

  defp enumerate_cardinalities(base_theory_path, cardinalities, max_models, output_root, opts) do
    total_model_target =
      length(cardinalities) * max_models

    carry_model_budget? =
      Keyword.fetch!(opts, :mode) != :consistency_check

    cardinalities
    |> Enum.reduce_while(
      {:ok, [], 0},
      fn cardinality, {:ok, results, carried_budget} ->
        cardinality_budget =
          max_models + carried_budget

        case enumerate_cardinality(base_theory_path, cardinality, cardinalities, cardinality_budget, output_root, opts) do
          {:ok, result} ->
            next_carried_budget =
              if carry_model_budget? do
                max(cardinality_budget - result.model_count, 0)
              else
                0
              end

            {:cont,
             {:ok, [result | results], next_carried_budget}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:ok, results, _unused_budget} ->
        results = Enum.reverse(results)

        {:ok,
         merge_cardinality_results(base_theory_path, output_root, results, total_model_target)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enumerate_cardinality(base_theory_path, cardinality, cardinalities, max_models, output_root, opts) do
    cardinality_output_dir = cardinality_output_dir(output_root, cardinality, cardinalities)

    search_theory_dir =
      cardinality_search_theory_dir(opts, cardinality_output_dir, cardinality, cardinalities)

    cardinality_opts =
      opts
      |> Keyword.put(:cardinality, cardinality)
      |> Keyword.put(:output_dir, cardinality_output_dir)
      |> Keyword.put(:search_theory_dir, search_theory_dir)

    with :ok <- ensure_output_dir(cardinality_output_dir),
         {:ok, initial_search_theory} <-
           SearchTheory.write(base_theory_path, [], cardinality_opts) do
      enumerate_cardinality_iterations(
        base_theory_path,
        initial_search_theory.theory_path,
        [],
        [],
        1,
        max_models,
        cardinality,
        cardinality_output_dir,
        cardinality_opts
      )
    end
  end

  defp default_input_theory_path do
    Path.expand(@default_input_theory, __DIR__)
  end

  defp ensure_output_dir(path) do
    case File.mkdir_p(path) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         {:cannot_create_output_directory,
          %{
            path: path,
            reason: reason
          }}}
    end
  end

  defp sanitize_path_part(value) do
    value
    |> String.replace(
      ~r/[^A-Za-z0-9_-]+/,
      "_"
    )
    |> String.trim("_")
  end

  defp enumerate_cardinality_iterations(
         base_theory_path,
         current_theory_path,
         blocking_axioms,
         completed_models,
         iteration,
         max_models,
         cardinality,
         output_root,
         opts
       ) do
    iteration_dir =
      Path.join(
        output_root,
        iteration_directory_name(iteration)
      )

    iteration_opts =
      opts
      |> Keyword.put(:iteration, iteration)
      |> Keyword.put(:cardinality, cardinality)
      |> Keyword.put(:base_theory_file, base_theory_path)
      |> Keyword.put(:output_dir, iteration_dir)
      |> Keyword.put(:workdir, Path.dirname(current_theory_path))
      |> Keyword.put(
        :blocking_name,
        default_blocking_name(base_theory_path, iteration)
      )

    case Iteration.run(current_theory_path, iteration_opts) do
      {:ok, %{status: status} = terminal_iteration}
      when status in [:no_countermodel, :no_model] ->
        terminal_iteration = Map.put(terminal_iteration, :cardinality, cardinality)

        {:ok,
         enumeration_result(
           :exhausted,
           base_theory_path,
           output_root,
           completed_models,
           terminal_iteration,
           cardinality
         )}

      {:ok, %{status: status} = model_result}
      when status in [:countermodel_found, :model_found] ->
        model_result = Map.put(model_result, :cardinality, cardinality)

        if iteration >= max_models do
          {:ok,
           enumeration_result(
             :max_models_reached,
             base_theory_path,
             output_root,
             completed_models ++ [model_result],
             nil,
             cardinality
           )}
        else
          updated_blocking_axioms =
            blocking_axioms ++ [model_result.blocking_axiom]

          case SearchTheory.write(
                 base_theory_path,
                 updated_blocking_axioms,
                 opts
               ) do
            {:ok, next_search_theory} ->
              completed_model =
                Map.put(
                  model_result,
                  :next_search_theory_file,
                  next_search_theory.theory_path
                )

              enumerate_cardinality_iterations(
                base_theory_path,
                next_search_theory.theory_path,
                updated_blocking_axioms,
                completed_models ++ [completed_model],
                iteration + 1,
                max_models,
                cardinality,
                output_root,
                opts
              )

            {:error, reason} ->
              {:error,
               {:search_theory_generation_failed,
                %{
                  iteration: iteration,
                  reason: reason,
                  completed_countermodels: completed_models ++ [model_result],
                  cardinality: cardinality
                }}}
          end
        end

      {:error, reason} ->
        {:error,
         {:enumeration_iteration_failed,
          %{
            iteration: iteration,
            search_theory_file: current_theory_path,
            reason: reason,
            completed_countermodels: completed_models,
            cardinality: cardinality
          }}}
    end
  end

  defp enumeration_result(
         status,
         base_theory_path,
         output_root,
         entries,
         terminal_iteration,
         cardinality
       ) do
    %{
      status: status,
      cardinality: cardinality,
      base_theory_file: base_theory_path,
      output_dir: output_root,
      model_count: length(entries),
      models: entries,
      svg_files:
        entries
        |> Enum.map(& &1.graph_svg_file)
        |> Enum.reject(&is_nil/1),
      tikz_files:
        entries
        |> Enum.map(& &1.graph_tikz_file)
        |> Enum.reject(&is_nil/1),
      pdf_files:
        entries
        |> Enum.map(& &1.graph_pdf_file)
        |> Enum.reject(&is_nil/1),
      blocking_axiom_files:
        entries
        |> Enum.map(& &1.blocking_axiom_file)
        |> Enum.reject(&is_nil/1),
      search_theory_files:
        entries
        |> Enum.map(&Map.get(&1, :next_search_theory_file))
        |> Enum.reject(&is_nil/1),
      terminal_iteration: terminal_iteration
    }
  end

  defp merge_cardinality_results(base_theory_path, output_root, cardinality_results, total_model_target) do
    models =
      Enum.flat_map(cardinality_results, & &1.models)

    terminal_iterations =
      cardinality_results
      |> Enum.map(& &1.terminal_iteration)
      |> Enum.reject(&is_nil/1)

    %{
      status: overall_enumeration_status(length(models), total_model_target),
      target_model_count: total_model_target,
      base_theory_file: base_theory_path,
      output_dir: output_root,
      model_count: length(models),
      models: models,
      svg_files: merge_artifact_files(cardinality_results, :svg_files),
      tikz_files: merge_artifact_files(cardinality_results, :tikz_files),
      pdf_files: merge_artifact_files(cardinality_results, :pdf_files),
      blocking_axiom_files: merge_artifact_files(cardinality_results, :blocking_axiom_files),
      search_theory_files: merge_artifact_files(cardinality_results, :search_theory_files),
      terminal_iteration:
        case cardinality_results do
          [result] -> result.terminal_iteration
          _results -> nil
        end,
      terminal_iterations: terminal_iterations,
      cardinality_results: cardinality_results
    }
  end

  defp merge_artifact_files(results, key) do
    Enum.flat_map(results, &Map.get(&1, key, []))
  end

  defp overall_enumeration_status(
         model_count,
         total_model_target
       )
       when model_count >= total_model_target do
    :max_models_reached
  end

  defp overall_enumeration_status(
         _model_count,
         _total_model_target
       ) do
    :exhausted
  end

  defp cardinality_output_dir(output_root, _cardinality, [_single_cardinality]) do
    output_root
  end

  defp cardinality_output_dir(output_root, cardinality, _cardinalities) do
    Path.join(output_root, cardinality_directory_name(cardinality))
  end

  defp cardinality_search_theory_dir(opts, cardinality_output_dir, cardinality, cardinalities) do
    case Keyword.fetch(opts, :search_theory_dir) do
      {:ok, directory} ->
        directory = Path.expand(directory)

        case cardinalities do
          [_single] ->
            directory

          _multiple ->
            Path.join(directory, cardinality_directory_name(cardinality))
        end

      :error ->
        Path.join(cardinality_output_dir, "search_theories")
    end
  end

  defp cardinality_directory_name(cardinality) do
    cardinality
    |> Integer.to_string()
    |> String.pad_leading(3, "0")
    |> then(&"cardinality_#{&1}")
  end

  defp validate_cardinalities(cardinalities) when is_list(cardinalities) do
    valid? =
      cardinalities != [] and
        Enum.all?(cardinalities, &(is_integer(&1) and &1 > 0)) and
        cardinalities ==
          cardinalities
          |> Enum.uniq()
          |> Enum.sort()

    if valid? do
      :ok
    else
      {:error,
       {:invalid_cardinalities,
        %{
          expected: :non_empty_sorted_unique_positive_integers,
          received: cardinalities
        }}}
    end
  end

  defp validate_cardinalities(cardinalities) do
    {:error,
     {:invalid_cardinalities,
      %{
        expected: :non_empty_sorted_unique_positive_integers,
        received: cardinalities
      }}}
  end

  defp validate_base_theory(path) do
    cond do
      not File.regular?(path) ->
        {:error,
         {:base_theory_not_found,
          %{
            path: path
          }}}

      Path.extname(path) != ".thy" ->
        {:error,
         {:invalid_base_theory_extension,
          %{
            path: path,
            expected: ".thy"
          }}}

      true ->
        with {:ok, source} <- File.read(path) do
          case Regex.run(~r/^\s*theory\s+([A-Za-z0-9_'.]+)/m, source, capture: :all_but_first) do
            [declared_name] ->
              expected_name =
                Path.basename(path, ".thy")

              if declared_name == expected_name do
                :ok
              else
                {:error,
                 {:theory_name_mismatch,
                  %{
                    path: path,
                    declared: declared_name,
                    expected: expected_name
                  }}}
              end

            nil ->
              {:error,
               {:missing_theory_declaration,
                %{
                  path: path
                }}}
          end
        end
    end
  end

  defp validate_max_models(max_models)
       when is_integer(max_models) and
              max_models > 0 do
    :ok
  end

  defp validate_max_models(max_models) do
    {:error,
     {:invalid_max_models,
      %{
        expected: :positive_integer,
        received: max_models
      }}}
  end

  defp iteration_directory_name(iteration) do
    iteration
    |> Integer.to_string()
    |> String.pad_leading(3, "0")
    |> then(&"iteration_#{&1}")
  end

  defp default_blocking_name(
         base_theory_path,
         iteration
       ) do
    base_name =
      base_theory_path
      |> Path.basename(".thy")
      |> sanitize_path_part()

    iteration_name =
      iteration
      |> Integer.to_string()
      |> String.pad_leading(3, "0")

    "#{base_name}_model_#{iteration_name}"
  end

  defp default_enumeration_output_dir(base_theory_path) do
    base_name =
      base_theory_path
      |> Path.basename(".thy")
      |> sanitize_path_part()

    Path.join([
      "out",
      base_name
    ])
  end
end
