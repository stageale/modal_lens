defmodule Src.Execution.Pipeline do
  @moduledoc """
  Executes one reproducible ModalLens analysis run.

  A pipeline run enumerates models for an Isabelle theory, performs
  structural graph analysis on the modal frame, reads the generated
  analysis report, prepares visual explanations, and optionally invokes
  the verbalizer.

  The resulting refinement candidates are reported but never applied by this module.
  """

  alias Src.Explanation.Verbal.Launcher, as: VerbalLauncher
  alias Src.Explanation.Visual.Highlight
  alias Src.Explanation.Visual.Palette
  alias Src.Explanation.Visual.Render
  alias Src.Execution.ArtifactStore
  alias Src.Execution.Run
  alias Src.Enumeration
  alias Src.Refinement.Axiom, as: RefinementAxiom
  alias Src.Refinement.Selection


  @graph_python_module "graph_ml.launcher"
  @graph_analysis_schema "modal-lens/graph-analysis-result"
  @graph_analysis_schema_version "1.0"

  @report_schema "modal-lens/analysis-report"
  @report_schema_version "1.1"

  @typedoc "The automatically selected structural refinement."
  @type selected_refinement :: %{
    candidate: map() | nil,
    axiom: String.t() | nil
  }

  @type result :: {:ok, Run.t(), map()} | {:error, term(), Run.t()}

  @doc "Executes one Isabelle theory within the given run."
  @spec run_theory(Run.t(), String.t()) :: result()
  def run_theory(%Run{} = run, theory_path)
      when is_binary(theory_path) do
    started_at = System.monotonic_time(:millisecond)

    case Run.start(run) do
      {:ok, running_run} ->
        with {:ok, enumeration_result} <-
               Enumeration.enumerate(
                 theory_path,
                 enumeration_options(running_run)
               ),
             {:ok, result} <-
               analyse_enumeration(
                 running_run,
                 theory_path,
                 enumeration_result
               ) do
          finish_success(running_run, result, started_at)
        else
          {:error, reason} ->
            finish_failure(running_run, reason, started_at)
        end

      {:error, reason} ->
        {:error, reason, run}
    end
  end

  @spec select_refinement([map()]) :: {:ok, selected_refinement()} | {:error, term()}
  defp select_refinement([]) do
    {:ok,
      %{
        candidate: nil,
        axiom: nil
      }
    }
  end

  defp select_refinement(candidates) do
    with {:ok, candidate} <- Selection.select(candidates),
        {:ok, axiom} <- render_refinement_axiom(candidate) do
          {:ok,
            %{
              candidate: candidate,
              axiom: axiom
            }
          }
        else
          {:error, reason} -> {:error, {:refinement_selection_failed, reason}}
        end
  end

  @spec render_refinement_axiom(map()) :: {:ok, String.t()} | {:error, term()}
  defp render_refinement_axiom(candidate) do
    try do
      {:ok,
        RefinementAxiom.refinement_axiom(candidate)
      }
    rescue
      error in ArgumentError ->
        {:error,
          {:refinement_axiom_rendering_failed,
            Exception.message(error)
          }
        }
    end
  end

  defp enumeration_options(%Run{} = run) do
    [
      mode: :countermodels,
      max_models:
        Map.get(
          run.params,
          :max_models,
          10
        ),
      output_dir: run.output_dir,
      model_logic:
        Map.get(
          run.params,
          :model_logic,
          :sdl
        ),
      relation:
        Map.get(
          run.params,
          :relation,
          "R"
        ),
      atoms:
        Map.get(
          run.params,
          :atoms,
          []
        ),
      auto_atoms:
        Map.get(
          run.params,
          :auto_atoms?,
          true
        ),
      render_atoms: render_atoms(run),
      render_graph:
        Map.get(
          run.params,
          :render_graph?,
          true
        ),
      graph_format:
        Map.get(
          run.params,
          :graph_format,
          :svg
        ),
      palette:
        Map.get(
          run.params,
          :palette,
          Palette.default()
        ),
      include_atoms:
        Map.get(
          run.params,
          :include_atoms?,
          true
        ),
      include_designated_world:
        Map.get(
          run.params,
          :include_designated_world?,
          true
        )
    ]
  end

  defp render_atoms(%Run{} = run) do
    case Map.get(run.params, :atoms, []) do
      [] -> nil
      atoms -> atoms
    end
  end

  defp analyse_enumeration(%Run{} = run, theory_path, enumeration_result) do
    model_json_files =
      enumeration_result.models
      |> Enum.map(& &1.model_json_file)

    case model_json_files do
      [] ->
        {:ok,
         Map.merge(enumeration_result, %{
           clusters: [],
           cluster_verbs: [],
           highlights: [],
           refinement_candidates: [],
           selected_refinement_candidate: nil,
           selected_refinement_axiom: nil,
           report_file: nil,
           graph_analysis: %{
             report_file: nil,
             model_count: 0,
             cluster_count: 0,
             refinement_candidate_count: 0
           }
         })}

      model_json_files ->
        with {:ok, graph_analysis} <- launch_graph_analysis(run, theory_path, model_json_files),
             {:ok, report} <- read_graph_report(graph_analysis.report_path),
              highlights = report["highlights"],
              refinement_candidates = report["refinement_candidates"],
             {:ok, selected_refinement} <- select_refinement(refinement_candidates),
             {:ok, models} <- apply_highlights(enumeration_result.models, highlights, run),
              clusters = build_clusters(report["clusters"], models),
             {:ok, cluster_verbs} <- maybe_verbalize_clusters(clusters, report, run) do
          {:ok,
            Map.merge(enumeration_result, %{
              models: models,
              clusters: clusters,
              cluster_verbs: cluster_verbs,
              highlights: highlights,
              refinement_candidates: refinement_candidates,
              selected_refinement_candidate: selected_refinement.candidate,
              selected_refinement_axiom: selected_refinement.axiom,
              report_file: graph_analysis.report_path,
              graph_analysis: graph_analysis.metadata
           })}
        end
    end
  end

  defp maybe_verbalize_clusters(clusters, report, %Run{} = run) do
    if Map.get(run.params, :verbalize?, false) do
      model_id = Map.fetch!(run.params, :verbalization_model)

      backend =
        Map.get(
          run.params,
          :verbalization_backend,
          "transformers"
        )

      launcher_options = [
        project_root:
          Map.get(
            run.params,
            :project_root,
            File.cwd!()
          ),
        uv_executable:
          Map.get(
            run.params,
            :uv_executable,
            "uv"
          ),
        output_name: ".",
        seed:
          Map.get(
            run.params,
            :verbalization_seed,
            42
          ),
        max_new_tokens:
          Map.get(
            run.params,
            :verbalization_max_new_tokens,
            768
          )
      ]

      clusters
      |> Enum.reduce_while(
        {:ok, []},
        fn cluster, {:ok, cluster_verbs} ->
          case maybe_verbalize_cluster(
                 cluster,
                 report,
                 run,
                 backend,
                 model_id,
                 launcher_options
               ) do
            {:ok, cluster_verb} ->
              {:cont, {:ok, [cluster_verb | cluster_verbs]}}

            {:error, reason} ->
              {:halt,
               {:error,
                {:cluster_verbalization_failed,
                 cluster.cluster_id, reason}}}
          end
        end
      )
      |> case do
        {:ok, cluster_verbs} ->
          {:ok, Enum.reverse(cluster_verbs)}

        {:error, _reason} = error ->
          error
      end
    else
      {:ok, []}
    end
  end

  defp maybe_verbalize_cluster(
         cluster,
         report,
         %Run{} = run,
         backend,
         model_id,
         launcher_options
       ) do
    cluster_id = cluster.cluster_id

    report_cluster =
      Enum.find(
        report["clusters"],
        &(&1["cluster_id"] == cluster_id)
      )

    cluster_dir =
      Path.join(
        run.output_dir,
        "verbalization/cluster-#{cluster_id}"
      )

    cluster_report_path =
      Path.join(cluster_dir, "report.json")

    with report_cluster when is_map(report_cluster) <-
           report_cluster,
         cluster_report =
           build_cluster_report(report, report_cluster),
         :ok <- File.mkdir_p(cluster_dir),
         :ok <-
           File.write(
             cluster_report_path,
             Jason.encode!(cluster_report, pretty: true) <> "\n"
           ),
         {:ok, launch} <-
           VerbalLauncher.launch(
             cluster_report_path,
             cluster_dir,
             backend,
             model_id,
             launcher_options
           ),
         artifacts when is_map(artifacts) <-
           launch.response["artifacts"],
         summary_path when is_binary(summary_path) <-
           artifacts["summary_json"],
         {:ok, summary_source} <- File.read(summary_path),
         {:ok, summary} <- Jason.decode(summary_source),
         cluster_summary when is_map(cluster_summary) <-
           List.first(summary["cluster_summaries"]) do
      {:ok,
       %{
         cluster_id: cluster_id,
         text: cluster_summary["summary"],
         notable_patterns:
           cluster_summary["notable_patterns"] || [],
         evidence: cluster_summary["evidence"] || [],
         limitations: summary["limitations"] || [],
         metadata: %{
           backend: backend,
           model_id: model_id
         },
         artifacts: %{
           report: cluster_report_path,
           request: launch.request_path,
           raw_output: artifacts["raw_output"],
           summary_json: artifacts["summary_json"],
           summary_markdown:
             artifacts["summary_markdown"],
           provenance: artifacts["provenance"]
         }
       }}
    else
      {:error, reason} ->
        {:error, reason}

      nil ->
        {:error, :missing_cluster_data}

      value when not is_map(value) ->
        {:error, {:invalid_cluster_data, value}}
    end
  end

  defp build_cluster_report(report, report_cluster) do
    report
    |> Map.put("clusters", [report_cluster])
    |> put_in(
      ["analysis", "model_count"],
      report_cluster["model_count"]
    )
    |> put_in(["analysis", "cluster_count"], 1)
    |> put_in(
      ["analysis", "reported_pattern_count"],
      length(
        report_cluster["characteristic_patterns"] || []
      )
    )
  end

  @spec read_graph_report(String.t()) :: {:ok, map()} | {:error, term()}
  defp read_graph_report(report_path) do
    with {:ok, source} <- File.read(report_path),
         {:ok, report} <- Jason.decode(source),
         schema when schema == @report_schema <- report["schema"],
         version when version == @report_schema_version <- report["schema_version"],
         clusters when is_list(clusters) <- report["clusters"],
         highlights when is_list(highlights)  <- report["highlights"],
         candidates when is_list(candidates) <- report["refinement_candidates"] do
      {:ok, report}
    else
      {:error, reason} ->
        {:error, {:cannot_read_graph_report, reason}}

      _other ->
        {:error, :invalid_graph_report}
    end
  end

  defp build_clusters(report_clusters, models) when is_list(report_clusters) and is_list(models) do
    models_by_index =
      models
      |> Enum.with_index()
      |> Map.new(fn {model, index} -> {index, model} end)

    Enum.map(report_clusters, fn cluster when is_map(cluster) ->
      model_indices =
        case Map.get(cluster, "model_indices", []) do
          indices when is_list(indices) -> indices
          _other -> []
        end

      representative_index =
        get_in(cluster, ["representative_model", "graph_index"])

      %{
        cluster_id: cluster["cluster_id"],
        model_count: cluster["model_count"],
        model_fraction: cluster["model_fraction"],
        model_indices: model_indices,
        characteristic_patterns: cluster["characteristic_patterns"] || [],
        representative_model_index: representative_index,
        representative_model: Map.get(models_by_index, representative_index),
        models: Enum.map(model_indices, &Map.get(models_by_index, &1))
      }
    end)
  end

  defp launch_graph_analysis(%Run{} = run, theory_path, model_json_files) when is_list(model_json_files) do
    report_path = Path.join(run.output_dir, "report.json")

    arguments = [
      "run",
      "python",
      "-m",
      @graph_python_module,
      "--theory",
      Path.expand(theory_path),
      "--output",
      report_path
    ] ++ model_json_files

    try do
      case System.cmd(
        Map.get(run.params, :uv_executable, "uv"),
        arguments,
        cd: Map.get(run.params, :project_root, File.cwd!()),
        stderr_to_stdout: true
      ) do
        {output, 0} ->
          response =
            output
            |> String.split("\n", trim: true)
            |> Enum.reverse()
            |> Enum.find_value(fn line ->
              case Jason.decode(line) do
                {:ok, %{} = value} -> value
                _ -> nil
              end
            end)
          case response do
            %{
              "schema" => @graph_analysis_schema,
              "schema_version" => @graph_analysis_schema_version,
              "status" => "completed",
              "report_path" => returned_report_path
            } when is_binary(returned_report_path) ->
              {:ok,
                %{
                  report_path: returned_report_path,
                  metadata: Map.drop(response, [
                    "schema",
                    "schema_version",
                    "status",
                    "report_path"
                  ])
                }
              }

            %{"status" => "error"} ->
              {:error, {:graph_analysis_failed, response}}

            _ ->
              {:error, {:invalid_graph_analysis_result, response}}
          end
        {output, status} -> {:error, {:graph_analysis_failed, status, output}}
      end
    rescue
      error -> {:error, {:graph_analysis_failed, Exception.message(error)}}
    end
  end

  defp apply_highlights(models, highlights, %Run{} = run) when is_list(models) and is_list(highlights) do
    highlights_by_graph =
      Map.new(
        highlights,
        &{&1["graph_index"], &1}
      )

    max_parallel_renderers =
      Map.get(
        run.params,
        :max_parallel_renderers,
        1
      )

    render_graph? =
      Map.get(
        run.params,
        :render_graph?,
        true
      )

    render_options = [
      atoms: render_atoms(run),
      palette:
        Map.get(
          run.params,
          :palette,
          Palette.default()
        )
    ]

    models
    |> Enum.with_index()
    |> Task.async_stream(
      fn {model_result, graph_index} ->
        graph_highlight =
          Map.get(
            highlights_by_graph,
            graph_index,
            %{}
          )
        try do
          {:ok,
          apply_model_highlight(
            model_result,
            graph_highlight,
            render_options,
            render_graph?
          )}
        rescue
          error ->
            {:error,
              {:highlight_failed,
                graph_index,
                Exception.message(error)}}
        end
      end,
      max_concurrency: max_parallel_renderers,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, model}}, {:ok, acc} ->
        {:cont, {:ok, [model | acc]}}

      {:ok, {:error, reason}}, _acc ->
        {:halt, {:error, reason}}

      {:exit, reason}, _acc ->
        {:halt,
          {:error, {:highlight_task_exit, reason}}}
      end)
    |> case do
      {:ok, highlighted_models} ->
        {:ok, Enum.reverse(highlighted_models)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_model_highlight(model_result, graph_highlight, render_options, render_graph?) do
    highlight = build_highlight(graph_highlight["highlight"])

    if render_graph? do
      render_model(model_result, Keyword.put(render_options, :highlight, highlight))
    end

    model_result
    |> Map.put(:cluster_id, graph_highlight["cluster_id"])
    |> Map.put(:highlight, highlight)
  end

  defp build_highlight(nil), do: nil

  defp build_highlight(source) when is_map(source) do
    Highlight.new(
      basis: :pattern,
      scope: :cluster,
      world_scores: Map.new(source["world_scores"] || [], &{&1["world"], &1["score"]}),
      edge_scores: Map.new(source["edge_scores"] || [], &{{&1["source"], &1["target"]}, &1["score"]}),
      tags: source["tags"] || [],
      metadata: source["metadata"] || %{}
    )
  end

  defp render_model(model_result, options) do
    Render.write_dot(model_result.model, model_result.graph_dot_file, options)

    Render.render_dot(model_result.graph_dot_file, fmt: "svg", output_path: model_result.graph_svg_file)

    Render.write_tikz(model_result.model, model_result.graph_tikz_file, options)

    if model_result.graph_pdf_file do
      Render.compile_tex(model_result.graph_tikz_file)
    end

    :ok
  end

  defp finish_success(%Run{} = run, experiment_result, started_at) do
    runtime_ms = System.monotonic_time(:millisecond) - started_at

    backend =
      experiment_result
      |> Map.get(:isabelle_run, %{})
      |> Map.get(:backend, Map.get(run.params, :backend, :local))

    with {:ok, run} <- register_artifacts(run, experiment_result),
         {:ok, run} <- Run.put_provenance(run, :backend, backend),
         {:ok, run} <- Run.put_metric(run, :runtime_ms, runtime_ms),
         {:ok, completed_run} <- Run.complete(run),
         {:ok, _manifest_path} <- ArtifactStore.persist(completed_run) do
      {:ok, completed_run, experiment_result}
    else
      {:error, reason} -> finish_failure(run, reason, started_at)
    end
  end

  defp finish_failure(%Run{} = run, reason, started_at) do
    runtime_ms = System.monotonic_time(:millisecond) - started_at

    with {:ok, run} <- Run.put_metric(run, :runtime_ms, runtime_ms),
         {:ok, failed_run} <- Run.fail(run, reason),
         {:ok, _manifest_path} <- ArtifactStore.persist(failed_run) do
      {:error, reason, failed_run}
    else
      {:error, persistence_reason} ->
        {:error, {:run_failure_not_persisted, reason, persistence_reason}, run}
    end
  end

  defp register_artifacts(%Run{} = run, result) do
    model_results =
      case Map.get(result, :models) do
        models when is_list(models) ->
          models

        _ ->
          [result]
      end

    run_artifacts = [
      {:report_json, result[:report_file]}
    ]

    model_artifacts =
      Enum.flat_map(model_results, fn model_result ->
        iteration =
          model_result
          |> Map.get(:iteration, 0)
          |> Integer.to_string()
          |> String.pad_leading(3, "0")

        prefix = "model_#{iteration}"

        [
          {"#{prefix}_nitpick_output",
           model_result[:nitpick_output_file]},
          {"#{prefix}_model_json",
           model_result[:model_json_file]},
          {"#{prefix}_graph_dot",
           model_result[:graph_dot_file]},
          {"#{prefix}_graph_svg",
           model_result[:graph_svg_file]},
          {"#{prefix}_graph_tikz",
           model_result[:graph_tikz_file]},
          {"#{prefix}_graph_pdf",
           model_result[:graph_pdf_file]},
          {"#{prefix}_blocking_axiom",
           model_result[:blocking_axiom_file]}
        ]
      end)

    verbalization_artifacts =
      result
      |> Map.get(:cluster_verbs, [])
      |> Enum.flat_map(fn cluster_verb ->
        cluster_id =
          cluster_verb
          |> Map.fetch!(:cluster_id)
          |> to_string()
          |> String.pad_leading(3, "0")

        artifacts = Map.get(cluster_verb, :artifacts, %{})
        prefix = "cluster_#{cluster_id}_verbalization"

        [
          {"#{prefix}_report", artifacts[:report]},
          {"#{prefix}_request", artifacts[:request]},
          {"#{prefix}_raw_output", artifacts[:raw_output]},
          {"#{prefix}_summary_json", artifacts[:summary_json]},
          {"#{prefix}_summary_markdown", artifacts[:summary_markdown]},
          {"#{prefix}_provenance", artifacts[:provenance]}
        ]
      end)

    Enum.reduce_while(
      run_artifacts ++ model_artifacts ++ verbalization_artifacts,
      {:ok, run},
      fn
        {_name, nil}, accumulator ->
          {:cont, accumulator}

        {name, path}, {:ok, current_run} ->
          case ArtifactStore.register(current_run, name, path) do
            {:ok, updated_run, _absolute_path} ->
              {:cont, {:ok, updated_run}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
      end
    )
  end
end
