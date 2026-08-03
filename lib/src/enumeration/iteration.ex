defmodule Src.Enumeration.Iteration do
  @moduledoc """
  Executes one Isabelle/Nitpick iteration of model enumeration.

  One iteration runs an existing search theory, parses the Nitpick result,
  and writes all artifacts associated with a discovered model.
  """

  alias Src.Core.BlockingAxiom
  alias Src.Core.Model
  alias Src.Core.Parser
  alias Src.Explanation.Visual.Palette
  alias Src.Explanation.Visual.Render
  alias Src.Serialization, as: Serial
  alias Src.Isabelle.Client

  @schema "axiom-refiner/model"
  @schema_version "1.0"


  @doc """
  Runs one complete model-enumeration iteration.

  The supplied theory must already contain the appropriate Nitpick command.
  """
  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(theory_path, opts \\ []) when is_binary(theory_path) and is_list(opts) do
    theory_path = Path.expand(theory_path)
    iteration = Keyword.get(opts, :iteration, 1)

    base_theory_file =
      opts
      |> Keyword.get(:base_theory_file, theory_path)
      |> Path.expand()

    output_dir =
      opts
      |> Keyword.get(:output_dir, default_output_dir(base_theory_file, iteration))
      |> Path.expand()

    nitpick_output_file = Path.join(output_dir, "nitpick.txt")

    isabelle_opts =
      Keyword.put(opts, :output_file, nitpick_output_file)

    with :ok <- validate_iteration(iteration),
         :ok <- ensure_output_dir(output_dir),
        {:ok, isabelle_run} <-
          Client.nitpick_theory(theory_path, isabelle_opts),
        {:ok, parsed_result} <-
          parse_nitpick_result(isabelle_run.output_file, opts) do
            case parsed_result do
              :no_result ->
                {:ok,
                  no_model_result(
                    base_theory_file,
                    isabelle_run,
                    output_dir,
                    iteration,
                    opts
                  )
                }
              model ->
                with {:ok, artifacts} <- write_countermodel_artifacts(
                  model,
                  base_theory_file,
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
                    )
                  }
                end
            end
          end

  end

  defp parse_nitpick_result(path, opts) do
    mode = Keyword.fetch!(opts, :mode)

    case File.read(path, opts) do
      {:ok, text} ->
        if no_nitpick_model?(text, mode) do
          {:ok, :no_result}
        else
          parse_model_text(text, path, opts)
        end

      {:error, reason} ->
        {:error,
          {:cannot_read_nitpic_output,
            %{
              file: path,
              reason: reason
            }
          }
        }
    end
  end

  defp no_nitpick_model?(text, :countermodels) do
    String.contains?(text, "Nitpick found no counterexample")
  end

  defp no_nitpick_model?(text, mode) when mode in [:satisfying_models, :consistency_check] do
    String.contains?(text, "Nitpick found no model")
  end

  defp parse_model_text(text, source, opts) do
    try do
      model =
        Parser.parse_nitpick_text(
          text,
          source: source,
          model_logic: Keyword.get(opts, :model_logic, :sdl),
          relation: Keyword.get(opts, :relation, "R"),
          atoms: Keyword.get(opts, :atoms, []),
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
            }
          }
        }
    end
  end

  defp write_countermodel_artifacts(model, base_theory_file, isabelle_run, output_dir, iteration, opts) do
    try do
      graph_dot_file =
        Path.join(output_dir, "model.dot")

      graph_svg_file =
        Path.join(output_dir, "model.svg")

      graph_tikz_file =
        Path.join(output_dir, "model.tex")

      render_options = [
        atoms: Keyword.get(opts, :render_atoms),
        highlight: Keyword.get(opts, :highlight),
        palette:
          Keyword.get(
            opts,
            :palette,
            Palette.default()
          )
      ]

      Render.write_dot(
        model,
        graph_dot_file,
        render_options
      )

      Render.render_dot(
        graph_dot_file,
        fmt: "svg",
        output_path: graph_svg_file
      )

      Render.write_tikz(
        model,
        graph_tikz_file,
        render_options
      )

      graph_pdf_file =
        case Keyword.get(opts, :graph_format, :svg) do
          :tikz ->
            Render.compile_tex(graph_tikz_file)

          "tikz" ->
            Render.compile_tex(graph_tikz_file)

          _other ->
            nil
        end

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
          include_atoms:
            Keyword.get(opts, :include_atoms, true),
          include_designated_world:
            Keyword.get(
              opts,
              :include_designated_world,
              false
            ),
          designated_world_constant:
            Keyword.get(
              opts,
              :designated_world_constant,
              Model.designated_world_constant(model)
            )
        )

      blocking_axiom_file =
        Path.join(output_dir, "blocking_axiom.thyfrag")

      File.write!(blocking_axiom_file, blocking_axiom <> "\n")

      model_json_file =
        Path.join(output_dir, "model.json")

      model_json =
        %{
          "schema" => @schema,
          "schema_version" => @schema_version,
          "metadata" => %{
            "iteration" => iteration,
            "mode" =>
              opts
              |> Keyword.fetch!(:mode)
              |> Atom.to_string(),
            "theory_name" =>
              isabelle_run.theory_name,
            "base_theory_file" =>
              Path.basename(base_theory_file),
            "search_theory_file" =>
              Path.basename(isabelle_run.theory_path)
          },
          "artifacts" => %{
            "nitpick_output" =>
              Path.basename(isabelle_run.output_file),
            "dot" => Path.basename(graph_dot_file),
            "json" => Path.basename(model_json_file),
            "svg" => Path.basename(graph_svg_file),
            "tikz" => Path.basename(graph_tikz_file),
            "pdf" =>
              if graph_pdf_file do
                Path.basename(graph_pdf_file)
              end,
            "blocking_axiom" =>
              Path.basename(blocking_axiom_file)
          },
          "model" =>
            model
            |> Model.to_export_map()
            |> Serial.safe()
        }

      File.write!(model_json_file, Jason.encode!(model_json, pretty: true) <> "\n")

      {:ok,
       %{
         graph_dot_file: graph_dot_file,
         graph_svg_file: graph_svg_file,
         graph_tikz_file: graph_tikz_file,
         graph_pdf_file: graph_pdf_file,
         model_json_file: model_json_file,
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
    result_metadata(
      base_theory_file,
      isabelle_run,
      output_dir,
      iteration,
      opts
    )
    |> Map.merge(%{
      status: model_status(model),
      model_kind: model.kind,
      model: model,
      model_summary: Model.as_summary(model),
      worlds: Model.world_indices(model),
      warnings: Model.warning_messages(model),
      graph_dot_file: artifacts.graph_dot_file,
      graph_svg_file: artifacts.graph_svg_file,
      graph_tikz_file: artifacts.graph_tikz_file,
      graph_pdf_file: artifacts.graph_pdf_file,
      model_json_file: artifacts.model_json_file,
      blocking_axiom: artifacts.blocking_axiom,
      blocking_axiom_file:
        artifacts.blocking_axiom_file,
      highlight: Keyword.get(opts, :highlight)
    })
  end

  defp no_model_result(
         base_theory_file,
         isabelle_run,
         output_dir,
         iteration,
         opts
       ) do
    result_metadata(
      base_theory_file,
      isabelle_run,
      output_dir,
      iteration,
      opts
    )
    |> Map.merge(%{
      status: no_model_status(Keyword.fetch!(opts, :mode)),
      model: nil,
      graph_dot_file: nil,
      graph_svg_file: nil,
      graph_tikz_file: nil,
      graph_pdf_file: nil,
      model_json_file: nil,
      blocking_axiom: nil,
      blocking_axiom_file: nil
    })
  end

  defp result_metadata(
         base_theory_file,
         isabelle_run,
         output_dir,
         iteration,
         opts
       ) do
    %{
      iteration: iteration,
      output_dir: output_dir,
      base_theory_file: base_theory_file,
      search_theory_file: isabelle_run.theory_path,
      theory_name: isabelle_run.theory_name,
      axiom_option: Keyword.get(opts, :axiom_option),
      nitpick_output_file: isabelle_run.output_file,
      isabelle_run: Map.drop(isabelle_run, [:log])
    }
  end

  defp model_status(%{kind: :countermodel}),
    do: :countermodel_found

  defp model_status(%{kind: :model}),
    do: :model_found

  defp no_model_status(:countermodels),
    do: :no_countermodel

  defp no_model_status(_mode),
    do: :no_model

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

end
