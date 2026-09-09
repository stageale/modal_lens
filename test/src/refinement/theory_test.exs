Code.require_file("../../support/refinement_helpers.exs", __DIR__)

defmodule Src.Refinement.TheoryTest do
  @moduledoc "Tests theory artifacts and cumulative imports across refinement rounds."
  use ExUnit.Case, async: true
  alias Src.Refinement.{Axiom, Theory, TestSupport}
  setup do: TestSupport.workspace()

  test "writes one axiom and a relative import into a separate directory", context do
    original = File.read!(context.theory)
    candidate = TestSupport.candidate()
    directory = Path.join(context.root, "rounds/one")
    assert {:ok, result} = Theory.write(context.theory, candidate,
      refinement_theory_dir: directory, theory_name: "First", axiom_name: "round_1")
    source = File.read!(result.theory_path)
    assert result.theory_path == Path.join(directory, "First.thy")
    assert result.base_theory_path == context.theory
    assert result.candidate_id == candidate["candidate_id"]
    assert result.refinement_axiom == Axiom.refinement_axiom(candidate, name: "round_1")
    assert source =~ "theory First"
    assert source =~ ~s(imports "../../Base")
    assert length(Regex.scan(~r/axiomatization where/, source)) == 1
    assert source =~ result.refinement_axiom
    assert File.read!(context.theory) == original
  end

  test "the second refinement imports the first refined theory", context do
    candidate = TestSupport.candidate()
    assert {:ok, first} = Theory.write(context.theory, candidate,
      refinement_theory_dir: Path.join(context.root, "first"))
    assert {:ok, second} = Theory.write(first.theory_path, candidate,
      refinement_theory_dir: Path.join(context.root, "second"))
    assert second.base_theory_path == first.theory_path
    assert second.theory_path != first.theory_path
    assert File.read!(second.theory_path) =~ ~s(imports "../first/#{first.theory_name}")
    assert File.read!(first.theory_path) =~ first.refinement_axiom
  end

  test "reports a missing base theory", context do
    missing = Path.join(context.root, "Missing.thy")
    assert Theory.write(missing, TestSupport.candidate()) == {:error, {:base_theory_not_found, missing}}
  end

  test "reports an output directory blocked by a regular file", context do
    blocked = Path.join(context.root, "blocked")
    File.write!(blocked, "occupied")
    assert {:error, {:cannot_create_refinement_directory, details}} =
      Theory.write(context.theory, TestSupport.candidate(), refinement_theory_dir: blocked)
    assert details.path == blocked
    assert File.read!(blocked) == "occupied"
  end
end
