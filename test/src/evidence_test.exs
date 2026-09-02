defmodule Src.EvidenceTest do
  use ExUnit.Case, async: true

  alias Src.Evidence

  test "creates formal model evidence" do
    assert {:ok, evidence} =
             Evidence.new(
               "model.3.cardinality",
               :model,
               :nitpick,
               %{cardinality: 3},
               %{iteration: 3}
             )

    assert evidence == %Evidence{
             id: "model.3.cardinality",
             kind: :model,
             source: :nitpick,
             payload: %{cardinality: 3},
             provenance: %{iteration: 3},
             assurance: :formal
           }
  end

  test "assigns assurance from the evidence kind" do
    assert Evidence.assurance_for(:model) == :formal
    assert Evidence.assurance_for(:proof) == :formal
    assert Evidence.assurance_for(:structural) == :deterministic
    assert Evidence.assurance_for(:learned) == :empirical
    assert Evidence.assurance_for(:operational) == :operational
  end

  test "creates learned evidence without allowing it to masquerade as formal evidence" do
    assert {:ok, evidence} =
             Evidence.new(
               "embedding.model.3",
               :learned,
               :rgcn,
               %{embedding: [0.1, 0.2, 0.3]}
             )

    assert evidence.kind == :learned
    assert evidence.assurance == :empirical
    assert evidence.provenance == %{}
  end

  test "creates operational evidence separately from semantic evidence" do
    assert {:ok, evidence} =
             Evidence.new(
               "leo_iii.run.7",
               :operational,
               :leo_iii,
               %{status: :timeout}
             )

    assert evidence.kind == :operational
    assert evidence.assurance == :operational
  end

  test "normalizes textual identifiers and sources" do
    assert {:ok, evidence} =
             Evidence.new(
               "  proof.step.1  ",
               :proof,
               "  leo-iii  ",
               %{formula: "$true"}
             )

    assert evidence.id == "proof.step.1"
    assert evidence.source == "leo-iii"
  end

  test "rejects empty identifiers" do
    assert {:error, {:invalid_id, "   "}} =
             Evidence.new(
               "   ",
               :model,
               :nitpick,
               %{}
             )
  end

  test "rejects unsupported evidence kinds" do
    assert {:error, {:invalid_kind, :prediction}} =
             Evidence.new(
               "result.1",
               :prediction,
               :some_backend,
               %{}
             )
  end

  test "rejects invalid sources" do
    assert {:error, {:invalid_source, ""}} =
             Evidence.new(
               "model.1",
               :model,
               "",
               %{}
             )

    assert {:error, {:invalid_source, 42}} =
             Evidence.new(
               "model.1",
               :model,
               42,
               %{}
             )
  end

  test "requires structured payloads" do
    assert {:error, {:invalid_payload, "three worlds"}} =
             Evidence.new(
               "model.1",
               :model,
               :nitpick,
               "three worlds"
             )
  end

  test "requires structured provenance" do
    assert {:error, {:invalid_provenance, "iteration 3"}} =
             Evidence.new(
               "model.1",
               :model,
               :nitpick,
               %{},
               "iteration 3"
             )
  end
end
