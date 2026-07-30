defmodule Src.Interface.Common.Service do
  @moduledoc """
  Executes one experiment as a reproducible run.

  The service connects the existing experiment pipeline with
  run state management and artifact persistence.
  """

  alias Src.Core.Model
  alias Src.Core.Render
  alias Src.Explanation.Verbal.Launcher, as: VerbalLauncher
  alias Src.Explanation.Visual.Highlight
  alias Src.Interface.Common.ArtifactStore
  alias Src.Interface.Common.Run
  alias Src.ModelEnumeration
  alias Src.Interface.Experiment

  @graph_python_module "graph_ml.launcher"

  @type result :: {:ok, Run.t(), map()} | {:error, term(), Run.t()}

  @doc "Executes one Isabelle theory within the given run."
  @spec run_theory(Run.t(), String.t(), boolean()) :: result()
  def run_theory(%Run{} = run, theory_path, experiment \\ false) when is_binary(theory_path) do
    started_at = System.monotonic_time(:millisecond)
    if experiment do
      experiment_opts =
        run.params
        |> Map.to_list()
        |> Keyword.put(:run_id, run.id)
        |> Keyword.put(:output_dir, run.output_dir)

      with {:ok, running_run} <- Run.start(run) do
        case Experiment.analyse_theory(theory_path, experiment_opts) do
          {:ok, experiment_result} ->
            case enrich_result(running_run, theory_path, experiment_result) do
              {:ok, enriched_result} -> finish_success(running_run, enriched_result, started_at)
              {:error, reason} -> finish_failure(running_run, reason, started_at)
            end
          {:error, reason} -> finish_failure(running_run, reason, started_at)
        end
      else
        {:error, reason} -> {:error, reason, run}
      end
    else
      enumeration_opts =
        run.params
        |> Map.to_list()
        |> Keyword.put(:mode, :countermodels)
        |> Keyword.put_new(:max_models, 10)
        |> Keyword.put(:output_dir, run.output_dir)
        |> Keyword.put(
          :render_atoms,
          case Map.get(run.params, :atoms, []) do
            [] -> nil
            atoms -> atoms
          end
        )
        |> Keyword.put(:include_designated_world, Map.get(run.params, :include_initial, true))
      with {:ok, running_run} <- Run.start(run) do
        case ModelEnumeration.enumerate(theory_path, enumeration_opts) do
          {:ok, enumeration_result} ->
            case analyse_enumeration(running_run, theory_path, enumeration_result) do
              {:ok, result} ->
                finish_success(running_run, result, started_at)
              {:error, reason} ->
                finish_failure(running_run, reason, started_at)
            end
          {:error, reason} ->
            finish_failure(running_run, reason, started_at)
        end
      else
        {:error, reason} -> {:error, reason, run}
      end
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
           report_file: nil,
           graph_analysis: %{
           report_file: nil,
             model_count: 0,
             cluster_count: 0
           }
         })}

      model_json_files ->
        with {:ok, graph_analysis} <- launch_graph_analysis(run, theory_path, model_json_files),
             {:ok, models} <- apply_highlights(enumeration_result.models, graph_analysis.highlights, run),
             {:ok, clusters} <- load_clusters(graph_analysis.report_path, models),
             {:ok, cluster_verbs} <- maybe_verbalize_clusters(clusters, graph_analysis.report_path, run) do
          {:ok,
            Map.merge(enumeration_result, %{
              models: models,
              clusters: clusters,
              cluster_verbs: cluster_verbs,
              report_file: graph_analysis.report_path,
              highlights: graph_analysis.highlights,
              graph_analysis: graph_analysis.metadata
           })}
        end
    end
  end

  defp maybe_verbalize_clusters(clusters, report_path, %Run{} = run) do
    if Map.get(run.params, :verbalize?, false) do
      model_id = Map.fetch!(run.params, :verbalization_model)

      backend = Map.get(run.params, :verbalization_backend, "transformers")

      with {:ok, source} <- File.read(report_path),
          {:ok, report} <- Jason.decode(source) do
            clusters
            |> Enum.reduce_while(
              {:ok, []},
              fn cluster, {:ok, cluster_verbs} ->
                cluster_id = cluster.cluster_id

                report_cluster =
                  Enum.find(report["clusters"], &(&1["cluster_id"] == cluster_id))

                cluster_dir = Path.join(run.output_dir, "verbalization/cluster-#{cluster_id}")

                cluster_report_path = Path.join(cluster_dir, "report.json")

                cluster_report =
                  report
                  |> Map.put("clusters", [report_cluster])
                  |> put_in(["analysis", "model_count"], report_cluster["model_count"])
                  |> put_in(["analysis", "cluster_count"],1)
                  |> put_in(["analysis", "reported_pattern_count"], length(report_cluster["characteristic_patterns"] || []))

                  launcher_options = [
                    project_root: Map.get(run.params, :project_root, File.cwd!()),
                    uv_executable: Map.get(run.params, :uv_executable, "uv"),
                    output_name: ".",
                    seed: Map.get(run.params, :verbalization_seed, 42),
                    max_new_tokens: Map.get(run.params, :verbalization_max_new_tokens, 768)
                  ]

                  with :ok <- File.mkdir_p(cluster_dir),
                      :ok <- File.write(cluster_report_path, Jason.encode!(cluster_report, pretty: true) <> "\n"),
                      {:ok, launch} <- VerbalLauncher.launch(
                        cluster_report_path,
                        cluster_dir,
                        backend,
                        model_id,
                        launcher_options
                      ),
                      artifacts = launch.response["artifacts"],
                      {:ok, summary_source} <- File.read(artifacts["summary_json"]),
                      {:ok, summary} <- Jason.decode(summary_source),
                      cluster_summary <- List.first(summary["cluster_summaries"]) do
                        cluster_verb = %{
                          cluster_id: cluster_id,
                          text: cluster_summary["summary"],
                          notable_patterns: cluster_summary["notable_patterns"] || [],
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
                            summary_markdown: artifacts["summary_markdown"],
                            provenance: artifacts["provenance"]
                          }
                        }

                        {:cont,
                          {:ok,
                            [cluster_verb | cluster_verbs]}}
                      else
                        {:error, reason} ->
                          {:halt,
                            {:error,
                              {:cluster_verbalization_failed, cluster_id, reason}}}
                      end
              end
            )
            |> case do
              {:ok, cluster_verbs} ->
                {:ok, Enum.reverse(cluster_verbs)}
              error ->
                error
            end
          end
    else
      {:ok, []}
    end
  end

  defp load_clusters(report_path, models) do
    with {:ok, source} <- File.read(report_path),
        {:ok, report} <- Jason.decode(source),
        clusters when is_list(clusters) <- report["clusters"] do
          {:ok,
            Enum.map(clusters, fn cluster ->
              model_indices =
                cluster["model_indices"] || []

              representative_index =
                get_in(cluster, ["representative_model", "graph_index"])

              %{
                cluster_id: cluster["cluster_id"],
                model_count: cluster["model_count"],
                model_fraction: cluster["model_fraction"],
                model_indices: model_indices,
                characteristic_patterns: cluster["characteristic_patterns"] || [],
                representative_model_index: representative_index,
                representative_model: Enum.at(models, representative_index),
                models: Enum.map(model_indices, &Enum.at(models, &1))
              }
            end)
          }
        else
          {:error, reason} ->
            {:error, {:cannot_read_graph_report, reason}}
          _ -> {:error, :invalid_graph_report}
        end
  end

  defp enrich_result(%Run{} = run, theory_path, experiment_result) do
    with {:ok, model_json_file} <- write_model_json(run, experiment_result),
         {:ok, graph_analysis} <- launch_graph_analysis(run, theory_path, [model_json_file]),
         {:ok, [experiment_result]} <- apply_highlights([experiment_result], run, graph_analysis.highlights) do
            experiment_result
            |> Map.merge(%{
              model_json_file: model_json_file,
              report_file: graph_analysis.report_path,
              graph_analysis: graph_analysis.metadata
            })
            |> maybe_verbalize(run)
         end
  end

  defp write_model_json(%Run{} = run, experiment_result) do
    payload = %{
      "metadata" => %{
        "run_id" => run.id,
        "iteration" => experiment_result.iteration,
        "theory_name" => experiment_result.theory_name
      },
      "model" =>
        experiment_result.model
        |> Model.to_export_map()
        |> Map.update!("edges", fn edges -> Enum.map(edges, &Tuple.to_list/1) end)
    }

    case ArtifactStore.write_json(run, :model_json, "model.json", payload) do
      {:ok, _run, path} -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
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
            %{"status" => "completed"} ->
              {:ok,
                %{
                  report_path: response["report_path"] || report_path,
                  highlights: response["highlights"] || [],
                  metadata: Map.drop(response, ["status", "report_path", "highlights"])
                }
              }
            _ -> {:error, {:graph_analysis_failed, output}}
          end
        {output, status} -> {:error, {:graph_analysis_failed, status, output}}
      end
    rescue
      error -> {:error, {:graph_analysis_failed, Exception.message(error)}}
    end
  end

  defp apply_highlights(models, highlights, %Run{} = run) do
    atoms =
      case Map.get(run.params, :atoms, []) do
        [] -> nil
        atoms -> atoms
      end

    palette =
      Map.get(run.params, :palette, :turbo)

    try do
      models =
        models
        |> Enum.with_index()
        |> Enum.map(fn {model_result, graph_index} ->
          graph_highlight =
            Enum.find(highlights, &(&1["graph_index"] == graph_index)) || %{}

          highlight_source =
            graph_highlight["highlight"]

          highlight =
            if is_map(highlight_source) do
              Highlight.new(
                basis: :pattern,
                scope: :cluster,
                world_scores:
                  Map.new(highlight_source["world_scores"] || [], fn entry -> {entry["world"], entry["score"]} end),
                edge_scores:
                  Map.new(highlight_source["edge_scores"] || [], fn entry -> { { entry["source"], entry["target"] }, entry["score"]} end),
                tags: highlight_source["tags"] || [],
                metadata:
                  highlight_source["metadata"] || %{}
              )
            end

          Render.write_dot(
            model_result.model,
            model_result.graph_dot_file,
            atoms: atoms,
            highlight: highlight,
            palette: palette
          )

          Render.render_dot(
            model_result.graph_dot_file,
            fmt: "svg",
            output_path: model_result.graph_svg_file
          )

          Render.write_tikz(
            model_result.model,
            model_result.graph_tikz_file,
            atoms: atoms,
            highlight: highlight,
            palette: palette
          )

          if model_result.graph_pdf_file do
            Render.compile_tex(model_result.graph_tikz_file)
          end

          model_result
          |> Map.put(
            :cluster_id,
            graph_highlight["cluster_id"]
          )
          |> Map.put(:highlight, highlight)
        end)

      {:ok, models}
    rescue
      error ->
        {:error,
         {:highlight_failed,
          Exception.message(error)}}
    end
  end

  defp maybe_verbalize(result, %Run{} = run) do
    if Map.get(run.params, :verbalize?, false) do
      model_id = Map.fetch!(run.params, :verbalization_model)

      opts = [
        project_root: Map.get(run.params, :project_root, File.cwd!()),
        uv_executable: Map.get(run.params, :uv_executable, "uv")
      ]

      with  {:ok, launch} <- VerbalLauncher.launch(
              result.report_file,
              Path.join(run.output_dir, "verbalization"),
              Map.get(run.params, :verbalization_backend, "transformers"),
              model_id,
              opts
            ),
          artifacts = launch.response["artifacts"],
          {:ok, explanation} <- File.read(artifacts["summary_markdown"]),
          {:ok, provenance} <- File.read(artifacts["provenance"]),
          {:ok, metadata} <- Jason.decode(provenance) do
            {:ok, Map.merge(result,
              %{
                llm_explanation: explanation,
                llm_metadata: metadata,
                verbalization_request_file: launch.request_path,
                verbalization_raw_output_file: artifacts["raw_output"],
                verbalization_summary_json_file: artifacts["summary_json"],
                verbalization_summary_file: artifacts["summary_markdown"],
                verbalization_provenance_file: artifacts["provenance"]
              })}
          end
    else
      {:ok, result}
    end
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

    top_level_artifacts = [
      {:report_json, result[:report_file]},
      {:verbalization_request,
       result[:verbalization_request_file]},
      {:verbalization_raw_output,
       result[:verbalization_raw_output_file]},
      {:verbalization_summary_json,
       result[:verbalization_summary_json_file]},
      {:verbalization_summary,
       result[:verbalization_summary_file]},
      {:verbalization_provenance,
       result[:verbalization_provenance_file]}
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

    Enum.reduce_while(
      top_level_artifacts ++ model_artifacts,
      {:ok, run},
      fn
        {_name, nil}, accumulator ->
          {:cont, accumulator}

        {name, path}, {:ok, current_run} ->
          case ArtifactStore.register(
                 current_run,
                 name,
                 path
               ) do
            {:ok, updated_run, _absolute_path} ->
              {:cont, {:ok, updated_run}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
      end
    )
  end
end
