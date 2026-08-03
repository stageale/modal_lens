defmodule Src.ModelEnumeration do
  @moduledoc """
  The module controls repeated model enumeration.

  Individual Isabelle/Nitpick iterations are executed by
  `Src.ModelEnumeration.Iteration`, while generated search theories are handled
  by `Src.ModelEnumeration.SearchTheory`.
  """

  alias Src.ModelEnumeration.Iteration
  alias Src.ModelEnumeration.SearchTheory

  @default_input_theory "../data/Input.thy"


  def enumerate(opts) when is_list(opts) do
    enumerate(default_input_theory_path(), opts)
  end


  @doc """
  Enumerates distinct countermodels for one fixed base theory.

  The base theory, selected axiom option, and investigated query remain fixed.
  For every discovered countermodel, a model-specific blocking axiom is added
  to a newly generated search theory.

  Options:

    * `:max_models`
      Maximum number of countermodels. Defaults to `5`.

    * `:output_dir`
      Root directory of the complete enumeration.

  All remaining options are forwarded to `run_iteration/2`.
  """
  def enumerate(base_theory_path, opts)
      when is_binary(base_theory_path) and is_list(opts) do

    base_theory_path = Path.expand(base_theory_path)

    mode = Keyword.fetch!(opts, :mode)

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

    search_theory_dir =
      opts
      |> Keyword.get(:search_theory_dir,Path.join(output_root, "search_theories"))
      |> Path.expand()

    enumeration_opts =
      opts
      |> Keyword.put(:output_dir, output_root)
      |> Keyword.put(:search_theory_dir, search_theory_dir)

    with :ok <- validate_base_theory(base_theory_path),
         :ok <- validate_max_models(max_models),
         :ok <- ensure_output_dir(output_root),
        {:ok, initial_search_theory} <- SearchTheory.write(base_theory_path, [], enumeration_opts) do
      enumerate(base_theory_path, initial_search_theory.theory_path, [], [], 1, max_models, output_root, enumeration_opts)
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

  defp enumerate(
         base_theory_path,
         current_theory_path,
         blocking_axioms,
         completed_models,
         iteration,
         max_models,
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
        {:ok,
         enumeration_result(
           :exhausted,
           base_theory_path,
           output_root,
           completed_models,
           terminal_iteration
         )}

      {:ok, %{status: status} = model_result}
      when status in [:countermodel_found, :model_found] ->
        if iteration >= max_models do
          {:ok,
           enumeration_result(
             :max_models_reached,
             base_theory_path,
             output_root,
             completed_models ++ [model_result],
             nil
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

              enumerate(
                base_theory_path,
                next_search_theory.theory_path,
                updated_blocking_axioms,
                completed_models ++ [completed_model],
                iteration + 1,
                max_models,
                output_root,
                opts
              )

            {:error, reason} ->
              {:error,
               {:search_theory_generation_failed,
                %{
                  iteration: iteration,
                  reason: reason,
                  completed_countermodels:
                    completed_models ++ [model_result]
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
            completed_countermodels: completed_models
          }}}
    end
  end

  defp enumeration_result(status, base_theory_path, output_root, entries, terminal_iteration) do
    %{
      status: status,
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
