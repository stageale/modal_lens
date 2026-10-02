import copy
import json

import pytest

from graph_ml.validate_refinement import main, occurrence_witness, validate_run


def occurrence():
    return {
        "size": 2,
        "pairwise_distinct": True,
        "worlds": [
            {"id": "u1", "valuations": {"p": True}},
            {"id": "u2", "valuations": {"p": False}},
        ],
        "relation_cells": [
            {"source": source, "target": target, "relation": "R",
             "holds": (source, target) == ("u1", "u2")}
            for source in ["u1", "u2"] for target in ["u1", "u2"]
        ],
    }


def model():
    return {"cardinality": 3, "relation": "R", "edges": [[1, 0], [2, 2]],
            "valuations": {"p": [False, True, True]}}


def test_occurrence_finds_permuted_substructure_inside_a_larger_model():
    assert occurrence_witness(model(), occurrence()) == {"u1": 1, "u2": 0}


def test_occurrence_requires_negative_cells_and_complete_valuations():
    extra_edge = model()
    extra_edge["edges"].append([0, 1])
    assert occurrence_witness(extra_edge, occurrence()) is None
    wrong_value = model()
    wrong_value["valuations"]["p"][0] = True
    assert occurrence_witness(wrong_value, occurrence()) is None


def test_occurrence_checks_each_modality_and_agent():
    candidate = occurrence()
    cells = candidate["relation_cells"]
    for cell in cells:
        cell.update(relation="RBel", agent="provider")
    other_cells = copy.deepcopy(cells)
    for cell in other_cells:
        cell.update(agent="authority", holds=False)
    candidate["relation_cells"] += other_cells
    multi = model()
    multi.pop("relation")
    multi.pop("edges")
    multi["modalities"] = [
        {"symbol": "RBel", "agent": "provider", "accessibility": [[1, 0]]},
        {"symbol": "RBel", "agent": "authority", "accessibility": []},
    ]
    assert occurrence_witness(multi, candidate) == {"u1": 1, "u2": 0}
    multi["modalities"][1]["accessibility"] = [[1, 0]]
    assert occurrence_witness(multi, candidate) is None
    multi["modalities"].pop()
    with pytest.raises(ValueError, match="missing candidate relations"):
        occurrence_witness(multi, candidate)


def write_run(tmp_path, *, violation=False):
    def write(path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))

    write(tmp_path / "refinement.json", {
        "iteration": [{
            "round": 1, "cluster_id": 0, "cluster_support": 0.5,
            "candidate_id": "candidate", "candidate": {"occurrence": occurrence()},
            "enumeration_before": {"model_count": 2},
            "enumeration_after": {"model_count": 1, "status": "partial_timeout"},
        }],
    })
    write(tmp_path / "report.json", {
        "clusters": [{"cluster_id": 0, "model_count": 2, "model_indices": [0, 1]}],
        "highlights": [{}, {}],
    })
    without_pattern = model()
    without_pattern["edges"] = []
    for index, data in enumerate([model(), without_pattern], 1):
        write(tmp_path / "cardinality_003" / f"iteration_{index:03d}" / "model.json",
              {"model": data})
    write(tmp_path / "refinement/round-001/cardinality_003/iteration_001/model.json",
          {"model": model() if violation else without_pattern})


def test_validation_does_not_claim_cluster_elimination_for_partial_support(tmp_path):
    write_run(tmp_path)
    result = validate_run(tmp_path)
    assert result["status"] == "passed"
    stage = result["rounds"][0]
    assert stage["measured_cluster_support"] == 0.5
    assert stage["all_observed_target_members_excluded"] is False
    assert stage["after_models_containing_pattern"] == 0
    assert stage["after_enumeration_status"] == "partial_timeout"


def test_validation_fails_and_records_a_witness_when_pattern_survives(tmp_path):
    write_run(tmp_path, violation=True)
    assert main([str(tmp_path), "--output", str(tmp_path / "audit.json")]) == 1
    result = json.loads((tmp_path / "audit.json").read_text())
    assert result["status"] == "failed"
    assert result["rounds"][0]["violations"][0]["witness"] == {"u1": 1, "u2": 0}


def test_validation_rejects_missing_model_files(tmp_path):
    write_run(tmp_path)
    (tmp_path / "cardinality_003/iteration_001/model.json").unlink()
    with pytest.raises(ValueError, match="Expected 2 model files"):
        validate_run(tmp_path)
