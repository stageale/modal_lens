from __future__ import annotations

import json
from pathlib import Path

import networkx as nx
import pytest

from graph_ml.report import build_report, write_report_json


def _graph() -> nx.DiGraph:
    graph = nx.DiGraph()
    graph.add_node(0, go=True, tell=False, designated=False)
    graph.add_node(1, go=False, tell=True, designated=True)
    graph.add_edge(0, 1, label="R")
    graph.graph.update(
        {
            "logic": "sdl",
            "kind": "countermodel",
            "relation": "R",
            "atoms": ("go", "tell"),
            "designated_world": {
                "index": 1,
                "name": "i2",
                "role": "initial_world",
            },
            "warnings": ["example warning"],
            "model_id": "model-0",
        }
    )
    return graph


def _highlights() -> list[dict]:
    return [
        {
            "graph_index": 0,
            "model_id": "model-0",
            "cluster_id": 0,
            "highlight": None,
        }
    ]


def test_build_report_uses_versioned_envelope_and_durable_highlights() -> None:
    report = build_report(
        theory="theory Example imports Main begin end",
        graphs=[_graph()],
        cluster_labels=[0],
        cluster_pattern_results={0: []},
        highlights=_highlights(),
    )

    assert report["schema"] == "axiom-refiner/analysis-report"
    assert report["schema_version"] == "1.0"
    assert report["highlights"] == _highlights()
    assert report["analysis"] == {
        "model_count": 1,
        "cluster_count": 1,
        "reported_pattern_count": 0,
    }

    representative = report["clusters"][0]["representative_model"]
    assert representative["atoms"] == ["go", "tell"]
    assert representative["designated_world"] == 1
    assert representative["warnings"] == ["example warning"]


def test_build_report_does_not_infer_designated_as_an_atom() -> None:
    graph = nx.DiGraph()
    graph.add_node(0, p=True, designated=True)
    graph.graph["designated_world"] = 0

    report = build_report(
        theory="theory Example imports Main begin end",
        graphs=[graph],
        cluster_labels=[0],
        cluster_pattern_results={0: []},
        highlights=[],
    )

    assert report["clusters"][0]["representative_model"]["atoms"] == ["p"]


def test_build_report_validates_parallel_inputs() -> None:
    with pytest.raises(ValueError, match="must match"):
        build_report(
            theory="Example",
            graphs=[_graph()],
            cluster_labels=[],
            cluster_pattern_results={},
            highlights=[],
        )

    with pytest.raises(ValueError, match="non-negative"):
        build_report(
            theory="Example",
            graphs=[_graph()],
            cluster_labels=[0],
            cluster_pattern_results={},
            highlights=[],
            max_patterns_per_cluster=-1,
        )


def test_write_report_json_persists_the_complete_contract(tmp_path: Path) -> None:
    output = tmp_path / "report.json"

    report = write_report_json(
        output,
        theory={"name": "Example"},
        graphs=[_graph()],
        cluster_labels=[0],
        cluster_pattern_results={0: []},
        highlights=_highlights(),
    )

    assert json.loads(output.read_text(encoding="utf-8")) == report
    assert report["highlights"] == _highlights()
