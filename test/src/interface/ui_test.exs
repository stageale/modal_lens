defmodule Src.Interface.UiTest do
  use ExUnit.Case, async: false

  alias Src.Interface.Ui

  setup do
    previous = System.get_env("MODAL_LENS_ISABELLE_BIN")

    root = tmp_dir()
    theory = Path.join(root, "Example.thy")

    File.write!(
      theory,
      "theory Example\nimports Main\nbegin\nend\n"
    )

    isabelle = Path.join(root, "isabelle")

    File.write!(
      isabelle,
      "#!/bin/sh\necho 'Nitpick found no counterexample'\n"
    )

    File.chmod!(isabelle, 0o755)
    System.put_env("MODAL_LENS_ISABELLE_BIN", isabelle)

    on_exit(fn ->
      if previous do
        System.put_env("MODAL_LENS_ISABELLE_BIN", previous)
      else
        System.delete_env("MODAL_LENS_ISABELLE_BIN")
      end
    end)

    {:ok, root: root, theory: theory}
  end

  test "runs variants with the serial default", %{root: root, theory: theory} do
    output = Path.join(root, "ui")

    options = [
      %{max_models: 1, verbalize?: false, render_graph?: false},
      %{max_models: 2, verbalize?: false, render_graph?: false}
    ]

    assert {:ok, session, page} = Ui.run(theory, output, options)

    assert File.exists?(page)
    assert length(session.variants) == 2
  end

  test "accepts bounded parallel variant execution", %{
    root: root,
    theory: theory
  } do
    output = Path.join(root, "parallel-ui")

    options = [
      %{max_models: 1, verbalize?: false, render_graph?: false},
      %{max_models: 2, verbalize?: false, render_graph?: false}
    ]

    assert {:ok, session, _page} =
             Ui.run(theory, output, options, max_parallel_runs: 2)

    assert Enum.sort(Enum.map(session.variants, & &1.run.id)) == ["ui-variant-1", "ui-variant-2"]

    assert File.dir?(Path.join(output, "ui-variant-1"))
    assert File.dir?(Path.join(output, "ui-variant-2"))
  end

  test "rejects invalid parallel run limits", %{
    root: root,
    theory: theory
  } do
    output = Path.join(root, "ui")

    assert {:error, {:invalid_max_parallel_runs, 0}} =
             Ui.run(
               theory,
               output,
               [%{}],
               max_parallel_runs: 0
             )

    assert {:error, {:invalid_max_parallel_runs, -1}} =
             Ui.run(
               theory,
               output,
               [%{}],
               max_parallel_runs: -1
             )
  end

  defp tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_ui_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end
end
