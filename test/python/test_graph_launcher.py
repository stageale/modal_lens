from __future__ import annotations

import json
from pathlib import Path

import networkx as nx

from graph_ml.launcher import (
    _analysis_feature_vector,
    _analysis_model_id,
    launch_analysis,
)


def test_launch_analysis_writes_versioned_report_and_minimal_result(
    tmp_path: Path,
) -> None:
    theory_file = tmp_path / "Example.thy"
    theory_file.write_text(
        "theory Example imports Main begin end\n",
        encoding="utf-8",
    )

    model_file = tmp_path / "model.json"
    model_file.write_text(
        json.dumps(
            {
                "schema": "modal-lens/model",
                "schema_version": "1.0",
                "metadata": {
                    "run_id": "variant-1",
                    "iteration": 1,
                    "cardinality": 3,
                    "theory_name": "Example",
                },
                "model": {
                    "logic": "sdl",
                    "kind": "countermodel",
                    "cardinality": 3,
                    "relation": "R",
                    "designated_world": {
                        "index": 0,
                        "name": "i1",
                        "role": "initial_world",
                    },
                    "atoms": ["p"],
                    "edges": [[0, 1], [1, 2]],
                    "valuations": {"p": [True, False, True]},
                    "warnings": [],
                },
            }
        ),
        encoding="utf-8",
    )

    report_file = tmp_path / "report.json"
    result = launch_analysis(
        [model_file],
        theory_path=theory_file,
        output_path=report_file,
    )
    report = json.loads(report_file.read_text(encoding="utf-8"))

    assert result["schema"] == "modal-lens/graph-analysis-result"
    assert result["schema_version"] == "1.0"
    assert result["status"] == "completed"
    assert result["model_count"] == 1
    assert result["report_path"] == str(report_file.resolve())
    assert result["include_cardinality_feature"] is False
    assert "highlight" not in result
    assert "highlights" not in result

    assert report["schema"] == "modal-lens/analysis-report"
    assert report["theory"]["name"] == "Example"
    assert report["highlights"][0]["graph_index"] == 0
    assert report["clusters"][0]["representative_model"]["model_id"] == "variant-1"


def test_analysis_feature_vector_excludes_cardinality_by_default() -> None:
    graph = nx.DiGraph()
    graph.add_nodes_from(
        [
            (0, {"designated": True}),
            (1, {"designated": False}),
            (2, {"designated": False}),
        ]
    )

    without_cardinality = _analysis_feature_vector(
        graph,
        feature_method="raw",
        graphlet_size=2,
        graphlet_occurrences=None,
        include_cardinality_feature=False,
    )
    with_cardinality = _analysis_feature_vector(
        graph,
        feature_method="raw",
        graphlet_size=2,
        graphlet_occurrences=None,
        include_cardinality_feature=True,
    )

    assert "worlds" not in without_cardinality
    assert with_cardinality["worlds"] == 3


def test_analysis_model_id_disambiguates_cardinalities() -> None:
    path = Path("model.json")

    assert (
        _analysis_model_id(
            {"iteration": 1, "cardinality": 2},
            path,
            multi_cardinality=True,
        )
        == "cardinality-002-model-001"
    )
    assert (
        _analysis_model_id(
            {"iteration": 1, "cardinality": 3},
            path,
            multi_cardinality=True,
        )
        == "cardinality-003-model-001"
    )
    assert (
        _analysis_model_id(
            {"iteration": 1, "cardinality": 3},
            path,
            multi_cardinality=False,
        )
        == "model-001"
    )
