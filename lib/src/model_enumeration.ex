defmodule Src.ModelEnumeration do
  @moduledoc """
  Orchestrates Isabelle/Nitpick countermodel enumeration.

  The module contains both:

    * `run_iteration/2` for one countermodel iteration,
    * `enumerate/2` for repeated model enumeration.

  For each discovered countermodel it stores:

    * the Nitpick output,
    * the parsed finite model,
    * DOT and SVG visualizations,
    * a model-specific blocking axiom,
    * the generated next search theory.

  LLM explanations and model-comparison analysis are deliberately outside the
  current implementation phase.
  """
  alias Src.Core.BlockingAxiom
  alias Src.Core.Model
  alias Src.Core.Parser
  alias Src.Core.Render
  alias Src.Interface.Isabelle.Client

  @default_input_theory "../data/Input.thy"
  @mode_theory_dir "../data/mod/"
  @blocking_marker "(* AXIOM_REFINER_BLOCKS *)"
  @search_theory_placeholder "AXIOM_REFINER_SEARCH"
  @input_theory_placeholder "AXIOM_REFINER_INPUT"

  @doc """
  Runs one complete countermodel iteration for an existing Isabelle theory.

  The theory must already contain the relevant Nitpick command.

  Important options:

    * `:iteration`
      Number of the current iteration. Defaults to `1`.

    * `:base_theory_file`
      Original unchanged DDL theory. For the first iteration this normally
      equals `theory_path`.

    * `:output_dir`
      Directory for the generated artifacts.

    * `:relation`
      Relation name expected in the Nitpick output. Defaults to `"R"`.

    * `:atoms`
      Unary predicates that should be parsed, for example `["go", "tell"]`.

    * `:auto_atoms`
      Whether unary predicates should be detected automatically.

    * `:axiom_option`
      Externally selected DDL axiom option or profile.

    * `:query`
      Formula investigated by the Isabelle theory.

    * `:highlight`
      Optional `Src.VisualExplanations.Highlight` value.

    * `:include_atoms`
      Whether valuations are included in the generated blocking axiom.

  Isabelle options such as `:isabelle_bin`, `:logic`, and `:threads`
  are forwarded to `Src.Interface.Isabelle.Client`.
  """
  def run_iteration(theory_path, opts \\ [])
      when is_binary(theory_path) and is_list(opts) do
    theory_path = Path.expand(theory_path)
    iteration = Keyword.get(opts, :iteration, 1)

    base_theory_file =
      opts
      |> Keyword.get(:base_theory_file, theory_path)
      |> Path.expand()

    output_dir =
      opts
      |> Keyword.get(
        :output_dir,
        default_output_dir(base_theory_file, iteration)
      )
      |> Path.expand()

    nitpick_output_file =
      Path.join(output_dir, "nitpick.txt")

    client_opts =
      Keyword.put(
        opts,
        :output_file,
        nitpick_output_file
      )

    with :ok <- validate_iteration(iteration),
         :ok <- ensure_output_dir(output_dir),
         {:ok, isabelle_run} <-
           Client.nitpick_theory(theory_path, client_opts),
         {:ok, parsed_result} <-
           parse_nitpick_result(
             isabelle_run.output_file,
             opts
           ) do
      case parsed_result do
        :no_result ->
          {:ok,
           no_model_result(
             base_theory_file,
             isabelle_run,
             output_dir,
             iteration,
             opts
           )}

        model ->
          # Create artifacts
          with {:ok, artifacts} <-
                 write_countermodel_artifacts(
                   model,
                   isabelle_run,
                   output_dir,
                   iteration,
                   opts
                 ) do
            {:ok,
             model_result(
               model,
               artifacts,
               base_theory_file,
               isabelle_run,
               output_dir,
               iteration,
               opts
             )}
          end
      end
    end
  end

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

    search_theory_opts =
      opts
      |> Keyword.put(:output_dir, output_root)
      |> Keyword.put_new(:search_theory_dir, Path.dirname(base_theory_path))

    search_theory_dir =
      opts
      |> Keyword.get(:search_theory_dir,Path.join(output_root, "search_theories"))
      |> Path.expand()

    enumeration_opts =
      opts
      |> Keyword.put(:search_theory_dir, search_theory_dir)

    with :ok <- validate_max_models(max_models),
         :ok <- ensure_output_dir(output_root),
        {:ok, initial_search_theory} <- write_search_theory(base_theory_path, [], search_theory_opts) do
      do_enumerate(base_theory_path, initial_search_theory.theory_path, [], [], 1, max_models, output_root, enumeration_opts)
    end
  end

  defp write_search_theory(base_theory_path, blocking_axioms, opts)
      when is_binary(base_theory_path) and
             is_list(blocking_axioms) and
             is_list(opts) do
    base_theory_path = Path.expand(base_theory_path)

    mode = Keyword.fetch!(opts, :mode)

    block_count = length(blocking_axioms)

    template_path = mode_theory_path(mode)

    base_theory_name = Path.basename(base_theory_path, ".thy")

    base_name = sanitize_path_part(base_theory_name)

    search_index =
      block_count
      |> Integer.to_string()
      |> String.pad_leading(3, "0")

    theory_name =
      "#{base_name}_Search_#{search_index}"

    theory_dir =
      opts
      |> Keyword.get(:search_theory_dir, Path.dirname(base_theory_path))
      |> Path.expand()

    base_theory_import =
      base_theory_path
      |> Path.rootname()
      |> Path.relative_to(theory_dir)
      |> String.replace("\\", "/")
      |> then(&~s("#{&1}"))

    theory_path =
      Path.join(theory_dir, "#{theory_name}.thy")

    with  :ok <- validate_blocking_axioms(blocking_axioms),
         {:ok, template} <- read_search_theory_template(template_path),
          :ok <- ensure_blocking_marker(template, template_path),
          :ok <- ensure_output_dir(theory_dir) do
      generated_source =
        template
        |> String.replace(
          @search_theory_placeholder,
          theory_name,
          global: false
        )
        |> String.replace(
          @input_theory_placeholder,
          base_theory_import,
          global: false
        )
        |> insert_blocking_axioms(blocking_axioms)

      with :ok <- write_generated_theory(theory_path, generated_source) do
        {:ok,
         %{
            mode: mode,
            theory_name: theory_name,
            theory_path: theory_path,
            template_path: template_path,
            base_theory_path: base_theory_path,
            base_theory_name: base_theory_name,
            block_count: block_count,
            blocking_axioms: blocking_axioms
         }}
      end
    end
  end

  defp default_input_theory_path do
    Path.expand(@default_input_theory, __DIR__)
  end

  defp mode_theory_path(mode) do
    @mode_theory_dir
    |> Path.join(mode_theory_file(mode))
    |> Path.expand(__DIR__)
  end

  defp mode_theory_file(:countermodels), do: "Countermodels.thy"
  defp mode_theory_file(:satisfying_models), do: "SatisfyingModels.thy"
  defp mode_theory_file(:consistency_check), do: "ConsistencyCheck.thy"

  defp parse_nitpick_result(path, opts) do
    mode = Keyword.fetch!(opts, :mode)
    case File.read(path) do
      {:ok, text} ->
        if no_nitpick_model?(text, mode) do
          {:ok, :no_result}
        else
          parse_model_text(text, path, opts)
        end

      {:error, reason} ->
        {:error,
         {:cannot_read_nitpick_output,
          %{
            file: path,
            reason: reason
          }}}
    end
  end

  defp no_nitpick_model?(text, :countermodels), do: String.contains?(text, "Nitpick found no counterexample")
  defp no_nitpick_model?(text, mode) when mode in [:satisfying_models, :consistency_check] do
    String.contains?(text, "Nitpick found no model")
  end

  defp parse_model_text(text, source, opts) do
    try do
      model =
        Parser.parse_nitpick_text(text,
          source: source,
          model_logic: Keyword.get(opts, :model_logic, :sdl),
          relation: Keyword.get(opts, :relation, "R"),
          atoms:
            opts
            |> Keyword.get(:atoms, [])
            |> normalize_atoms(),
          auto_atoms: Keyword.get(opts, :auto_atoms, false)
        )

      {:ok, model}
    rescue
      error in ArgumentError ->
        {:error,
         {:nitpick_parse_failed,
          %{
            file: source,
            message: Exception.message(error)
          }}}
    end
  end

  defp write_countermodel_artifacts(
         model,
         isabelle_run,
         output_dir,
         iteration,
         opts
       ) do
    try do
      graph_dot_file =
        Path.join(output_dir, "model.dot")

      graph_svg_file =
        Path.join(output_dir, "model.svg")

      Render.write_dot(
        model,
        graph_dot_file,
        atoms: Keyword.get(opts, :render_atoms),
        highlight: Keyword.get(opts, :highlight)
      )

      Render.render_dot(
        graph_dot_file,
        fmt: "svg",
        output_path: graph_svg_file
      )

      blocking_name =
        Keyword.get(
          opts,
          :blocking_name,
          "#{isabelle_run.theory_name}_model_#{iteration}"
        )

      blocking_axiom =
        BlockingAxiom.blocking_axiom(
          model,
          name: blocking_name,
          include_atoms: Keyword.get(opts, :include_atoms, true),
          include_designated_world: Keyword.get(opts, :include_designated_world, false),
          designated_world_constant: Keyword.get(opts, :designated_world_constant, Model.designated_world_constant(model))
        )

      blocking_axiom_file =
        Path.join(
          output_dir,
          "blocking_axiom.thyfrag"
        )

      File.write!(
        blocking_axiom_file,
        blocking_axiom <> "\n"
      )

      {:ok,
       %{
         graph_dot_file: graph_dot_file,
         graph_svg_file: graph_svg_file,
         blocking_axiom: blocking_axiom,
         blocking_axiom_file: blocking_axiom_file
       }}
    rescue
      error in [File.Error, RuntimeError] ->
        {:error,
         {:artifact_generation_failed,
          %{
            output_dir: output_dir,
            message: Exception.message(error)
          }}}
    end
  end

  defp model_result(
         model,
         artifacts,
         base_theory_file,
         isabelle_run,
         output_dir,
         iteration,
         opts
       ) do
    %{
      status: model_status(model),
      model_kind: model.kind,
      iteration: iteration,
      output_dir: output_dir,
      base_theory_file: base_theory_file,
      search_theory_file: isabelle_run.theory_path,
      theory_name: isabelle_run.theory_name,
      axiom_option: Keyword.get(opts, :axiom_option),
      nitpick_output_file: isabelle_run.output_file,
      model: model,
      model_summary: Model.as_summary(model),
      worlds: Model.world_indices(model),
      warnings: Model.warning_messages(model),
      graph_dot_file: artifacts.graph_dot_file,
      graph_svg_file: artifacts.graph_svg_file,
      blocking_axiom: artifacts.blocking_axiom,
      blocking_axiom_file: artifacts.blocking_axiom_file,
      highlight: Keyword.get(opts, :highlight),
      isabelle_run: Map.drop(isabelle_run, [:log])
    }
  end

  defp model_status(%{kind: :countermodel}), do: :countermodel_found
  defp model_status(%{kind: :model}), do: :model_found

  defp no_model_result(
         base_theory_file,
         isabelle_run,
         output_dir,
         iteration,
         opts
       ) do
    status =
      case Keyword.fetch!(opts, :mode) do
        :countermodels -> :no_countermodel
        _ -> :no_model
      end
    %{
      status: status,
      iteration: iteration,
      output_dir: output_dir,
      base_theory_file: base_theory_file,
      search_theory_file: isabelle_run.theory_path,
      theory_name: isabelle_run.theory_name,
      axiom_option: Keyword.get(opts, :axiom_option),
      nitpick_output_file: isabelle_run.output_file,
      model: nil,
      graph_dot_file: nil,
      graph_svg_file: nil,
      blocking_axiom: nil,
      blocking_axiom_file: nil,
      isabelle_run: Map.drop(isabelle_run, [:log])
    }
  end

  defp validate_iteration(iteration)
       when is_integer(iteration) and iteration > 0 do
    :ok
  end

  defp validate_iteration(iteration) do
    {:error,
     {:invalid_iteration,
      %{
        expected: :positive_integer,
        received: iteration
      }}}
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

  defp default_output_dir(
         base_theory_file,
         iteration
       ) do
    theory_name =
      base_theory_file
      |> Path.basename(".thy")
      |> sanitize_path_part()

    iteration_name =
      iteration
      |> Integer.to_string()
      |> String.pad_leading(3, "0")
      |> then(&"iteration_#{&1}")

    Path.join([
      "out",
      theory_name,
      iteration_name
    ])
  end

  defp sanitize_path_part(value) do
    value
    |> String.replace(
      ~r/[^A-Za-z0-9_-]+/,
      "_"
    )
    |> String.trim("_")
  end

  defp normalize_atoms(nil), do: []
  defp normalize_atoms(""), do: []
  defp normalize_atoms("-"), do: []

  defp normalize_atoms(atoms)
       when is_binary(atoms) do
    atoms
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_atoms(atoms)
       when is_list(atoms) do
    atoms
  end

  defp do_enumerate(base_theory_path, current_theory_path, blocking_axioms, entries, iteration, max_models, output_root, opts) do
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

    case run_iteration(current_theory_path, iteration_opts) do
      {:ok, %{status: status} = terminal_iteration}
      when status in [:no_countermodel, :no_model] ->
        {:ok,
         enumeration_result(
           :exhausted,
           base_theory_path,
           output_root,
           entries,
           terminal_iteration
         )}

      {:ok, %{status: status} = entry}
      when status in [:countermodel_found, :model_found] ->
        updated_entries =
          entries ++ [entry]

        cond do
          iteration >= max_models ->
            {:ok,
             enumeration_result(
               :max_models_reached,
               base_theory_path,
               output_root,
               updated_entries,
               nil
             )}

          true ->
            updated_blocking_axioms =
              blocking_axioms ++
                [entry.blocking_axiom]

            case write_search_theory(
                   base_theory_path,
                   updated_blocking_axioms,
                   opts
                 ) do
              {:ok, next_search_theory} ->
                entry_with_next_theory =
                  Map.put(
                    entry,
                    :next_search_theory_file,
                    next_search_theory.theory_path
                  )

                updated_entries =
                  List.replace_at(
                    updated_entries,
                    -1,
                    entry_with_next_theory
                  )

                do_enumerate(
                  base_theory_path,
                  next_search_theory.theory_path,
                  updated_blocking_axioms,
                  updated_entries,
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
                    completed_countermodels: updated_entries
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
            completed_countermodels: entries
          }}}
    end
  end

  defp enumeration_result(
         status,
         base_theory_path,
         output_root,
         entries,
         terminal_iteration
       ) do
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

  defp read_search_theory_template(path) do
    case File.read(path) do
      {:ok, source} ->
        {:ok, source}

      {:error, reason} ->
        {:error,
         {:cannot_read_search_theory_template,
          %{
            path: path,
            reason: reason
          }}}
    end
  end

  defp ensure_blocking_marker(source, path) do
    if String.contains?(source, @blocking_marker) do
      :ok
    else
      {:error,
       {:missing_blocking_marker,
        %{
          path: path,
          expected_marker: @blocking_marker
        }}}
    end
  end

  defp insert_blocking_axioms(source, blocking_axioms) do
    rendered_blocks =
      blocking_axioms
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {axiom, index} ->
        """
        (* Automatically generated blocking axiom #{index}. *)
        #{axiom}
        """
        |> String.trim()
      end)

    replacement =
      """
      #{rendered_blocks}

      #{@blocking_marker}
      """
      |> String.trim()

    String.replace(
      source,
      @blocking_marker,
      replacement,
      global: false
    )
  end

  defp write_generated_theory(path, source) do
    case File.write(path, source) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         {:cannot_write_search_theory,
          %{
            path: path,
            reason: reason
          }}}
    end
  end

  defp validate_blocking_axioms(blocking_axioms) do
    if Enum.all?(
         blocking_axioms,
         fn axiom ->
           is_binary(axiom) and
             String.trim(axiom) != ""
         end
       ) do
      :ok
    else
      {:error, {:invalid_blocking_axioms, blocking_axioms}}
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
