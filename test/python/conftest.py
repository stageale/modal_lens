from __future__ import annotations

from copy import deepcopy

import pytest


@pytest.fixture
def sample_report() -> dict:
    return {
        "schema": "modal-lens/analysis-report",
        "schema_version": "1.0",
        "generated_at": "2026-07-26T12:00:00+00:00",
        "purpose": "normative_gap_analysis",
        "scope": {
            "goal": "Identify recurring structural indicators of possible normative gaps.",
            "creates_new_norms": False,
            "refinement_role": "diagnostic_support_for_human_deliberation",
        },
        "theory": {
            "name": "Example",
            "source": "examples/input/Example.thy",
            "content": "theory Example imports Main begin end",
        },
        "analysis": {
            "model_count": 2,
            "cluster_count": 1,
            "reported_pattern_count": 1,
        },
        "clusters": [
            {
                "cluster_id": 0,
                "model_count": 2,
                "model_fraction": 1.0,
                "model_indices": [0, 1],
                "characteristic_patterns": [
                    {
                        "pattern_id": "cluster-0-pattern-1",
                        "pattern": ["graphlet", 2, ["example"]],
                        "cluster_support": 1.0,
                        "outside_support": 0.0,
                        "contrast": 1.0,
                        "occurring_model_count": 2,
                        "representative_occurrence": {
                            "model_id": "model-0",
                            "graph_index": 0,
                            "worlds": [0, 1],
                        },
                    }
                ],
                "representative_model": {
                    "model_id": "model-0",
                    "graph_index": 0,
                    "logic": "sdl",
                    "kind": "countermodel",
                    "cardinality": 2,
                    "relation": "R",
                    "designated_world": 0,
                    "atoms": ["p"],
                    "worlds": [
                        {"id": 0, "valuations": {"p": True}},
                        {"id": 1, "valuations": {"p": False}},
                    ],
                    "edges": [{"source": 0, "target": 1}],
                    "warnings": ["example warning"],
                },
            }
        ],
        "highlights": [
            {
                "graph_index": 0,
                "model_id": "model-0",
                "cluster_id": 0,
                "highlight": {
                    "basis": "pattern",
                    "scope": "cluster",
                    "world_scores": [
                        {"world": 0, "score": 1.0},
                        {"world": 1, "score": 1.0},
                    ],
                    "edge_scores": [
                        {"source": 0, "target": 1, "score": 1.0}
                    ],
                    "tags": ["strongest_characteristic_pattern"],
                    "metadata": {"cluster_id": 0},
                },
            },
            {
                "graph_index": 1,
                "model_id": "model-1",
                "cluster_id": 0,
                "highlight": None,
            },
        ],
    }


@pytest.fixture
def sample_summary() -> dict:
    return {
        "overview": "The analysis contains one cluster with two countermodels.",
        "cluster_summaries": [
            {
                "cluster_id": 0,
                "summary": "Cluster 0 contains both analyzed countermodels.",
                "notable_patterns": ["cluster-0-pattern-1"],
                "evidence": [
                    "cluster.0.model_count",
                    "cluster.0.model_fraction",
                ],
            }
        ],
        "limitations": [
            "The summary is restricted to the supplied analysis facts."
        ],
    }


@pytest.fixture
def copied_report(sample_report: dict) -> dict:
    return deepcopy(sample_report)
