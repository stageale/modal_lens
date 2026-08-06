defmodule Src.Enumeration.IterationTest do
  use ExUnit.Case

  alias Src.Core.Model.SDL
  alias Src.Enumeration.Iteration

  setup do
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      if previous_path do
        System.put_env("PATH", previous_path)
      else
        System.delete_env("PATH")
      end
    end)

    :ok
  end

  test "validates iteration numbers before invoking Isabelle" do
    assert {:error, {:invalid_iteration, details}} =
             Iteration.run("missing.thy",
               iteration: 0,
               mode: :countermodels,
               output_dir: tmp_dir("invalid_iteration")
             )

    assert details.expected == :positive_integer
    assert details.received == 0
  end

  test "returns a terminal no-countermodel result" do
    dir = tmp_dir("no_result")
    theory = write_theory(dir, "No_Result")

    isabelle =
      write_executable(
        dir,
        "fake_isabelle",
        "cat <<'OUT'\nNitpick found no counterexample\nOUT\n"
      )

    assert {:ok, result} =
             Iteration.run(theory,
               mode: :countermodels,
               isabelle_bin: isabelle,
               output_dir: Path.join(dir, "out")
             )

    assert result.status == :no_countermodel
    assert result.model == nil
    assert result.graph_dot_file == nil
    assert File.read!(result.nitpick_output_file) =~ "Nitpick found no counterexample"
  end

  test "writes a versioned model artifact and can suppress graph rendering" do
    dir = tmp_dir("model")
    theory = write_theory(dir, "Model_Result")

    isabelle =
      write_executable(
        dir,
        "fake_isabelle",
        "cat <<'OUT'\nNitpick found a counterexample for card i = 1:\nw = i⇩1\nR = (i⇩1, i⇩1) := True\np = (λx. _) (i⇩1 := True)\nOUT\n"
      )

    assert {:ok, result} =
             Iteration.run(theory,
               mode: :countermodels,
               model_logic: :sdl,
               atoms: ["p"],
               render_graph: false,
               isabelle_bin: isabelle,
               output_dir: Path.join(dir, "out")
             )

    assert result.status == :countermodel_found
    assert %SDL{} = result.model
    assert result.model.valuations == %{"p" => [true]}
    assert result.graph_dot_file == nil
    assert result.graph_svg_file == nil
    assert result.graph_tikz_file == nil
    assert result.graph_pdf_file == nil

    document = result.model_json_file |> File.read!() |> Jason.decode!()
    assert document["schema"] == "modal-lens/model"
    assert document["schema_version"] == "1.0"
    assert document["metadata"]["iteration"] == 1
    assert document["model"]["logic"] == "sdl"
    assert document["model"]["edges"] == [[0, 0]]
    assert document["artifacts"]["dot"] == nil
    assert document["artifacts"]["svg"] == nil
    assert document["artifacts"]["tikz"] == nil
    assert document["artifacts"]["pdf"] == nil
  end

  defp write_theory(dir, name) do
    path = Path.join(dir, "#{name}.thy")
    File.write!(path, "theory #{name}\nimports Main\nbegin\nend\n")
    path
  end

  defp write_executable(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\nset -e\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  defp tmp_dir(label) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_iteration_#{label}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
