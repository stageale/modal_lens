from __future__ import annotations

from copy import deepcopy

import pytest

from verbalization.facts import (
    build_verbalization_facts,
    canonical_verbalization_facts_bytes,
    verbalization_facts_sha256,
)


def _facts_by_id(verbalization_facts: dict) -> dict[str, dict]:
    return {
        fact["id"]: fact
        for fact in verbalization_facts["facts"]
    }


def test_build_verbalization_facts_extracts_report_evidence(
    sample_report,
):
    result = build_verbalization_facts(sample_report)
    facts = _facts_by_id(result)

    assert result["schema_version"] == "1.0"
    assert result["source"] == {
        "report_schema_version": "1.1",
        "verbalization_mode": "grounded",
    }
    assert facts["analysis.model_count"]["value"] == 2
    assert facts["cluster.0.model_count"]["value"] == 2
    assert facts[
        "cluster.0.pattern.cluster-0-pattern-1.cluster_support"
    ]["value"] == 1.0
    assert facts[
        "cluster.0.representative_model.edges"
    ]["value"] == [{"source": 0, "target": 1}]


def test_build_verbalization_facts_excludes_volatile_and_theory_text(
    sample_report,
):
    result = build_verbalization_facts(sample_report)
    fact_ids = {
        fact["id"]
        for fact in result["facts"]
    }

    assert "generated_at" not in fact_ids
    assert "theory.content" not in fact_ids
    assert "theory.name" in fact_ids
    assert "theory.source" in fact_ids


def test_interpretive_facts_include_theory_content(sample_report):
    result = build_verbalization_facts(
        sample_report,
        verbalization_mode="interpretive",
    )
    facts = _facts_by_id(result)

    assert result["source"]["verbalization_mode"] == "interpretive"
    assert facts["theory.content"]["value"] == sample_report["theory"]["content"]


def test_build_verbalization_facts_sorts_fact_ids(
    sample_report,
):
    result = build_verbalization_facts(sample_report)
    fact_ids = [
        fact["id"]
        for fact in result["facts"]
    ]

    assert fact_ids == sorted(fact_ids)
    assert len(fact_ids) == len(set(fact_ids))


def test_build_verbalization_facts_copies_values(
    sample_report,
):
    result = build_verbalization_facts(sample_report)
    sample_report["clusters"][0]["model_indices"].append(99)

    facts = _facts_by_id(result)

    assert facts["cluster.0.model_indices"]["value"] == [0, 1]


def test_verbalization_facts_hash_ignores_generated_at(
    sample_report,
):
    changed_report = deepcopy(sample_report)
    changed_report["generated_at"] = "2099-01-01T00:00:00+00:00"

    first = build_verbalization_facts(sample_report)
    second = build_verbalization_facts(changed_report)

    assert first == second
    assert verbalization_facts_sha256(first) == verbalization_facts_sha256(second)


def test_canonical_verbalization_facts_bytes_are_compact_and_stable():
    first = {
        "b": 2,
        "a": 1,
    }
    second = {
        "a": 1,
        "b": 2,
    }

    assert canonical_verbalization_facts_bytes(first) == b'{"a":1,"b":2}'
    assert canonical_verbalization_facts_bytes(first) == (
        canonical_verbalization_facts_bytes(second)
    )


def test_build_verbalization_facts_rejects_unsupported_schema(
    sample_report,
):
    sample_report["schema_version"] = "2.0"

    with pytest.raises(
        ValueError,
        match="Unsupported report schema version",
    ):
        build_verbalization_facts(sample_report)


def test_build_verbalization_facts_rejects_missing_required_field(
    sample_report,
):
    del sample_report["analysis"]["model_count"]

    with pytest.raises(
        ValueError,
        match="analysis.model_count",
    ):
        build_verbalization_facts(sample_report)


def test_build_verbalization_facts_rejects_duplicate_cluster_ids(
    sample_report,
):
    duplicate = deepcopy(sample_report["clusters"][0])
    sample_report["clusters"].append(duplicate)
    sample_report["analysis"]["cluster_count"] = 2

    with pytest.raises(
        ValueError,
        match="Duplicate fact id: cluster.0.cluster_id",
    ):
        build_verbalization_facts(sample_report)


def test_build_verbalization_facts_rejects_unknown_mode(sample_report):
    with pytest.raises(ValueError, match="Unsupported verbalization mode"):
        build_verbalization_facts(
            sample_report,
            verbalization_mode="expansive",
        )
