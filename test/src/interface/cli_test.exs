defmodule Src.Interface.CLITest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Src.Interface.CLI

  test "prints usage for help" do
    output =
      capture_io(fn ->
        assert CLI.main(["help"]) == 0
      end)

    assert output =~ "Usage:"
    assert output =~ "summary"
    assert output =~ "axiom"
  end

  test "summary prints compact model information" do
    path =
      tmp_file("simple_countermodel.txt", """
      Nitpick found a counterexample for card i = 2:
        Constants:
          (R) =
            (λx. _)
            ((i⇩1, i⇩1) := True, (i⇩1, i⇩2) := False,
             (i⇩2, i⇩1) := False, (i⇩2, i⇩2) := True)
          w = i⇩1
      """)

    output =
      capture_io(fn ->
        assert CLI.main(["summary", path]) == 0
      end)

    assert output =~ path
    assert output =~ "countermodel"
    assert output =~ "card=2"
    assert output =~ "relation=R"
    assert output =~ "edges=2"
  end

  test "summary reports missing input" do
    output =
      capture_io(:stderr, fn ->
        assert CLI.main(["summary"]) == 1
      end)

    assert output =~ "No input files given"
  end

  defp tmp_file(filename, content) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "axiom_refiner_cli_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    path = Path.join(dir, filename)
    File.write!(path, content)
    path
  end

  test "rank prints ranked axiom table" do
    path = tmp_file("rank_countermodel.txt", nitpick_with_atoms())

    output =
      capture_io(fn ->
        assert CLI.main(["rank", path, "--atoms", "go,tell"]) == 0
      end)

    assert output =~ "score\tviolations\tsupport\taffected_models\taxiom"
    assert output =~ "serial"
    assert output =~ "reflexive"
    assert output =~ "transitive"
  end

  test "rank honors limit option" do
    path = tmp_file("rank_limited_countermodel.txt", nitpick_with_atoms())

    output =
      capture_io(fn ->
        assert CLI.main(["rank", path, "--atoms", "go,tell", "--limit", "2"]) == 0
      end)

    lines =
      output
      |> String.split("\n", trim: true)

    assert length(lines) == 3
    assert hd(lines) == "score\tviolations\tsupport\taffected_models\taxiom"
  end

  test "rank reports missing input" do
    output =
      capture_io(:stderr, fn ->
        assert CLI.main(["rank"]) == 1
      end)

    assert output =~ "No input files given"
  end

  defp nitpick_with_atoms do
    """
    Nitpick found a counterexample for card i = 2:
      Constants:
        go =
          (λx. _)
          (i⇩1 := True, i⇩2 := False)
        tell =
          (λx. _)
          (i⇩1 := False, i⇩2 := True)
        (R) =
          (λx. _)
          ((i⇩1, i⇩1) := True, (i⇩1, i⇩2) := True,
           (i⇩2, i⇩1) := False, (i⇩2, i⇩2) := False)
        w = i⇩1
    """
  end
end
