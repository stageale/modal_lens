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
