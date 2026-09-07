from __future__ import annotations

import math

import pytest

from graph_ml.refinement import derive_exclusion_candidate


def _pattern(*, support: float = 0.75, outside: float = 0.25, contrast: float = 0.5):
    return {
        "pattern": [
            "graphlet",
            2,
            [
                [["p"], []],
                [[1, "R"], [0, None], [0, None], [0, None]],
            ],
        ],
        "cluster_support": support,
        "outside_support": outside,
        "contrast": contrast,
    }


def test_derives_language_neutral_exact_induced_exclusion() -> None:
    candidate = derive_exclusion_candidate(
        _pattern(),
        cluster_id=3,
        rank=2,
        atoms=["q", "p"],
        relation="R",
    )

    assert candidate["schema"] == "modal-lens/refinement-candidate"
    assert candidate["schema_version"] == "1.0"
    assert candidate["candidate_id"] == "refinement-cluster-3-pattern-2"
    assert candidate["kind"] == "exact_induced_graphlet_exclusion"
    assert candidate["status"] == "candidate"
    assert candidate["origin"]["pattern_id"] == "cluster-3-pattern-2"
    assert candidate["origin"]["cluster_support"] == 0.75
    assert candidate["origin"]["outside_support"] == 0.25
    assert candidate["occurrence"]["pairwise_distinct"] is True
    assert [world["id"] for world in candidate["occurrence"]["worlds"]] == ["u1", "u2"]
    assert candidate["occurrence"]["worlds"][0]["valuations"] == {"p": True, "q": False}
    assert len(candidate["occurrence"]["relation_cells"]) == 4
    assert candidate["refinement"] == {
        "rule": "exclude_exact_induced_occurrence",
        "operator": "not",
        "operand": "occurrence",
    }


def test_preserves_negative_cells_and_full_signature() -> None:
    candidate = derive_exclusion_candidate(
        _pattern(), cluster_id=0, rank=1, atoms=["p", "q"], relation="R"
    )
    cells = candidate["occurrence"]["relation_cells"]
    assert [(cell["source"], cell["target"], cell["holds"]) for cell in cells] == [
        ("u1", "u1", True),
        ("u1", "u2", False),
        ("u2", "u1", False),
        ("u2", "u2", False),
    ]
    assert all(set(world["valuations"]) == {"p", "q"} for world in candidate["occurrence"]["worlds"])


@pytest.mark.parametrize(
    ("field", "value", "message"),
    [
        ("cluster_id", True, "Cluster ID"),
        ("rank", 0, "Pattern rank"),
        ("relation", "", "Relation name"),
    ],
)
def test_rejects_invalid_control_arguments(field, value, message: str) -> None:
    arguments = {"cluster_id": 0, "rank": 1, "atoms": ["p"], "relation": "R"}
    arguments[field] = value
    with pytest.raises((TypeError, ValueError), match=message):
        derive_exclusion_candidate(_pattern(), **arguments)


@pytest.mark.parametrize(
    ("pattern", "message"),
    [
        (["wrong", 2, []], "Unsupported pattern kind"),
        (["graphlet", 0, []], "Graphlet size"),
        (["graphlet", 2, [[], []]], "Node-label count"),
        (["graphlet", 2, [[["x"], []], []]], "outside the supplied signature"),
        (["graphlet", 2, [[["p"], []], [[1, "S"], [0, None], [0, None], [0, None]]]], "single relation"),
        (["graphlet", 2, [[["p"], []], [[0, "R"], [0, None], [0, None], [0, None]]]], "Negative relation cell"),
    ],
)
def test_rejects_malformed_graphlet_patterns(pattern, message: str) -> None:
    with pytest.raises((TypeError, ValueError), match=message):
        derive_exclusion_candidate(
            {**_pattern(), "pattern": pattern},
            cluster_id=0,
            rank=1,
            atoms=["p"],
            relation="R",
        )


@pytest.mark.parametrize(
    ("field", "value"),
    [("cluster_support", math.nan), ("outside_support", 1.1), ("contrast", -1.1)],
)
def test_rejects_nonfinite_or_out_of_range_scores(field: str, value: float) -> None:
    with pytest.raises((TypeError, ValueError)):
        derive_exclusion_candidate(
            {**_pattern(), field: value},
            cluster_id=0,
            rank=1,
            atoms=["p"],
            relation="R",
        )
