defmodule Src.Execution.PipelineTest do
  use ExUnit.Case

  alias Src.Execution.ArtifactStore
  alias Src.Execution.Pipeline
  alias Src.Execution.Run

  setup do
    previous = System.get_env("MODAL_LENS_ISABELLE_BIN")

    on_exit(fn ->
      if previous do
        System.put_env("MODAL_LENS_ISABELLE_BIN", previous)
      else
        System.delete_env("MODAL_LENS_ISABELLE_BIN")
      end
    end)

    :ok
  end

  test "completes and persists a run when enumeration finds no countermodel" do
    root = tmp_dir()
    theory = Path.join(root, "Example.thy")
    File.write!(theory, "theory Example\nimports Main\nbegin\nend\n")

    isabelle = Path.join(root, "isabelle")
    File.write!(isabelle, "#!/bin/sh\necho 'Nitpick found no counterexample'\n")
    File.chmod!(isabelle, 0o755)
    System.put_env("MODAL_LENS_ISABELLE_BIN", isabelle)

    output_dir = Path.join(root, "run")

    assert {:ok, run} =
             Run.new("pipeline-no-model", output_dir, %{
               max_models: 1,
               model_logic: :sdl,
               relation: "R",
               atoms: [],
               auto_atoms?: true,
               render_graph?: false,
               max_parallel_renderers: 1,
               graph_format: :svg,
               palette: :turbo,
               include_atoms?: true,
               include_designated_world?: true,
               verbalize?: false,
               verbalization_model: "unused"
             })

    assert {:ok, completed_run, result} = Pipeline.run_theory(run, theory)
    assert completed_run.status == :completed
    assert result.status == :exhausted
    assert result.model_count == 0
    assert result.clusters == []
    assert result.highlights == []
    assert result.report_file == nil

    assert {:ok, manifest} = ArtifactStore.read_manifest(completed_run)
    assert manifest["status"] == "completed"
    assert is_integer(manifest["metrics"]["runtime_ms"])
  end

  test "preserves per-cardinality enumeration summaries in run provenance" do
    root = tmp_dir()
    theory = Path.join(root, "Multi.thy")
    File.write!(theory, "theory Multi\nimports Main\nbegin\nend\n")

    isabelle =
      write_executable(root, "isabelle_multi", "echo 'Nitpick found no counterexample'\n")

    System.put_env("MODAL_LENS_ISABELLE_BIN", isabelle)

    assert {:ok, run} =
             Run.new("pipeline-cardinalities", Path.join(root, "run-cardinalities"), %{
               cardinalities: [2, 3],
               max_models: 1,
               model_logic: :sdl,
               relation: "R",
               atoms: [],
               auto_atoms?: true,
               render_graph?: false,
               graph_format: :svg,
               palette: :turbo,
               include_atoms?: true,
               include_designated_world?: true,
               include_cardinality_feature?: false,
               verbalize?: false,
               verbalization_model: "unused"
             })

    assert {:ok, completed_run, result} = Pipeline.run_theory(run, theory)
    assert Enum.map(result.cardinality_results, & &1.cardinality) == [2, 3]

    summaries = completed_run.provenance["enumeration_by_cardinality"]
    assert Enum.map(summaries, & &1.cardinality) == [2, 3]
    assert Enum.all?(summaries, &(&1.status == :exhausted))
    assert Enum.all?(summaries, &(&1.model_count == 0))
  end

  test "passes the cardinality feature opt-in to graph analysis" do
    root = tmp_dir()
    theory = Path.join(root, "Graph.thy")
    File.write!(theory, "theory Graph\nimports Main\nbegin\nend\n")

    isabelle =
      write_executable(
        root,
        "isabelle_graph",
        "printf 'Nitpick found a counterexample for card i = 1:\n'\n"
      )

    uv =
      write_executable(
        root,
        "uv",
        ~S"""
        printf '%s\n' "$*" > "$(dirname "$0")/uv.calls"
        output=''
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --output) output=$2; shift 2;;
            *) shift;;
          esac
        done
        cat > "$output" <<'JSON'
        {"schema":"modal-lens/analysis-report","schema_version":"1.1","analysis":{"model_count":1,"cluster_count":1,"reported_pattern_count":0,"refinement_candidate_count":0,"signature":{"atoms":[],"relation":"R"}},"refinement_candidates":[],"clusters":[{"cluster_id":0,"model_count":1,"model_fraction":1.0,"model_indices":[0],"characteristic_patterns":[],"representative_model":{"graph_index":0}}],"highlights":[{"graph_index":0,"model_id":"model-001","cluster_id":0,"highlight":null}]}
        JSON
        printf '{"schema":"modal-lens/graph-analysis-result","schema_version":"1.0","status":"completed","report_path":"%s","model_count":1,"cluster_count":1,"include_cardinality_feature":true}\n' "$output"
        """
      )

    System.put_env("MODAL_LENS_ISABELLE_BIN", isabelle)

    assert {:ok, run} =
             Run.new("pipeline-cardinality-feature", Path.join(root, "run-feature"), %{
               cardinalities: [1],
               max_models: 1,
               model_logic: :sdl,
               relation: "R",
               atoms: [],
               auto_atoms?: true,
               render_graph?: false,
               graph_format: :svg,
               palette: :turbo,
               include_atoms?: true,
               include_designated_world?: true,
               include_cardinality_feature?: true,
               verbalize?: false,
               verbalization_model: "unused",
               uv_executable: uv,
               project_root: root
             })

    assert {:ok, _completed_run, result} = Pipeline.run_theory(run, theory)
    assert File.read!(Path.join(root, "uv.calls")) =~ "--cardinality-feature"
    assert result.graph_analysis["include_cardinality_feature"] == true
  end

  defp write_executable(root, name, body) do
    path = Path.join(root, name)
    File.write!(path, "#!/bin/sh\nset -eu\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_pipeline_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
