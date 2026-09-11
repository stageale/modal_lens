from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path

import pytest

from verbalization.base import GenerationResult, Verbalizer
from verbalization.facts import build_verbalization_facts, verbalization_facts_sha256
from verbalization.pipeline import _render_refinement_summary_markdown, run_verbalization, write_verbalization_result
from verbalization.prompt import (
    INTERPRETIVE_REFINEMENT_SYSTEM_MESSAGE,
    REFINEMENT_SYSTEM_MESSAGE,
    build_verbalization_messages,
    render_refinement_user_message,
)
from verbalization.summary_schema import (
    SummarySchemaError,
    parse_and_validate_summary_json,
    validate_summary_schema,
)


def _candidate(round_number: int) -> dict:
    return {
        "schema": "modal-lens/refinement-candidate",
        "schema_version": "1.0",
        "candidate_id": "refinement-cluster-0-pattern-1",
        "kind": "exact_induced_graphlet_exclusion",
        "status": "candidate",
        "origin": {
            "pattern_id": "cluster-0-pattern-1",
            "cluster_id": 0,
            "rank": 1,
            "cluster_support": 0.75 if round_number == 1 else 0.5,
            "outside_support": 0.25,
            "contrast": 0.5 if round_number == 1 else 0.25,
        },
        "occurrence": {"size": 2, "pairwise_distinct": True},
        "refinement": {
            "rule": "exclude_exact_induced_occurrence",
            "operator": "not",
            "operand": "occurrence",
        },
    }


def refinement_report() -> dict:
    iterations = []
    before = {"status": "max_models_reached", "model_count": 2}
    for round_number in (1, 2):
        after = (
            {"status": "max_models_reached", "model_count": 2}
            if round_number == 1
            else {"status": "exhausted", "model_count": 0}
        )
        iterations.append(
            {
                "round": round_number,
                "input_theory_path": f"/tmp/round-{round_number - 1}.thy",
                "refined_theory_path": f"/tmp/round-{round_number}.thy",
                "run_id": f"run-{round_number}",
                "output_dir": f"/tmp/run-{round_number}",
                "candidate": _candidate(round_number),
                "candidate_id": "refinement-cluster-0-pattern-1",
                "pattern_id": "cluster-0-pattern-1",
                "cluster_id": 0,
                "cluster_support": _candidate(round_number)["origin"]["cluster_support"],
                "outside_support": 0.25,
                "graphlet_size": 2,
                "refinement_axiom": f"axiomatization where ax_round_{round_number}: True",
                "enumeration_before": before,
                "enumeration_after": after,
            }
        )
        before = after

    return {
        "schema": "modal-lens/refinement-report",
        "schema_version": "1.0",
        "status": "completed",
        "stop_reason": "max_rounds",
        "applied_refinement_count": 2,
        "initial": {
            "theory_path": "/tmp/input.thy",
            "theory": {
                "path": "/tmp/input.thy",
                "content": "theory Input imports Main begin end",
            },
            "run_id": "run-0",
            "output_dir": "/tmp/run-0",
            "enumeration": {"status": "max_models_reached", "model_count": 2},
        },
        "iteration": iterations,
        "final": {
            "theory_path": "/tmp/round-2.thy",
            "theory": {
                "path": "/tmp/round-2.thy",
                "content": "theory Round2 imports Round1 begin end",
            },
            "run_id": "run-2",
            "output_dir": "/tmp/run-2",
            "enumeration": {"status": "exhausted", "model_count": 0},
        },
    }


class FakeVerbalizer(Verbalizer):
    def __init__(self, summary: dict):
        self.summary = summary
        self.last_messages = None

    @property
    def backend(self) -> str:
        return "fake"

    @property
    def model_id(self) -> str:
        return "fake/model"

    def generate(self, request):
        self.last_messages = request.messages
        return GenerationResult(self.backend, self.model_id, json.dumps(self.summary), {"test": True})


def _facts(report: dict | None = None) -> dict:
    return build_verbalization_facts(report or refinement_report())


def test_projects_all_refinement_rounds_with_round_scoped_evidence() -> None:
    facts = _facts()
    by_id = {fact["id"]: fact for fact in facts["facts"]}
    assert facts["source"] == {
        "report_schema": "modal-lens/refinement-report",
        "report_schema_version": "1.0",
        "verbalization_mode": "grounded",
    }
    assert by_id["refinement.stop_reason"]["value"] == "max_rounds"
    assert by_id["initial.enumeration.status"]["value"] == "max_models_reached"
    assert by_id["final.enumeration.model_count"]["value"] == 0
    assert by_id["round.1.refinement_axiom"]["value"].startswith("axiomatization")
    assert by_id["round.2.enumeration_after.status"]["value"] == "exhausted"
    assert by_id["round.1.candidate_id"]["value"] == by_id["round.2.candidate_id"]["value"]
    assert [fact["id"] for fact in facts["facts"]] == sorted(by_id)
    assert verbalization_facts_sha256(facts) == verbalization_facts_sha256(_facts(deepcopy(refinement_report())))
    assert "model_count_delta" not in by_id


def test_rejects_missing_round_observations_and_duplicate_round_ids() -> None:
    missing = refinement_report()
    del missing["iteration"][0]["enumeration_after"]
    with pytest.raises(ValueError, match="enumeration_after"):
        build_verbalization_facts(missing)

    duplicate = refinement_report()
    duplicate["iteration"][1]["round"] = 1
    with pytest.raises(ValueError, match="Duplicate fact id"):
        build_verbalization_facts(duplicate)


def test_refinement_prompt_requires_rounds_and_limits_claims() -> None:
    facts = _facts()
    message = render_refinement_user_message(facts)
    assert '"round_summaries"' in message
    assert "round.1." in message
    assert "round.2." in message
    assert "applied" in REFINEMENT_SYSTEM_MESSAGE
    assert "constitute a proof" in REFINEMENT_SYSTEM_MESSAGE
    assert "global validity" in REFINEMENT_SYSTEM_MESSAGE
    assert build_verbalization_messages(facts)[0]["content"] == REFINEMENT_SYSTEM_MESSAGE


def test_interpretive_refinement_prompt_uses_theory_sources() -> None:
    facts = build_verbalization_facts(
        refinement_report(),
        verbalization_mode="interpretive",
    )
    by_id = {fact["id"]: fact for fact in facts["facts"]}

    messages = build_verbalization_messages(
        facts,
        verbalization_mode="interpretive",
    )

    assert by_id["initial.theory.content"]["value"].startswith("theory Input")
    assert by_id["final.theory.content"]["value"].startswith("theory Round2")
    assert messages[0]["content"] == INTERPRETIVE_REFINEMENT_SYSTEM_MESSAGE
    assert "local Kripke semantics" in messages[0]["content"]
    assert "strengthens the preceding theory" in messages[1]["content"]


def test_refinement_summary_validation_requires_existing_round_scoped_evidence() -> None:
    facts = _facts()
    valid = {
        "overview": "Two structural refinement rounds were applied.",
        "overview_evidence": ["refinement.applied_refinement_count", "final.enumeration.status"],
        "round_summaries": [
            {"round": 1, "summary": "The first candidate was applied.", "evidence": ["round.1.refinement_axiom"]},
            {"round": 2, "summary": "The second candidate was applied.", "evidence": ["round.2.enumeration_after.status"]},
        ],
        "limitations": ["Enumeration was bounded.", "Application does not prove logical validity."],
    }
    assert validate_summary_schema(valid, verbalization_facts=facts) == ()
    parse_and_validate_summary_json(json.dumps(valid), verbalization_facts=facts)

    invalid = deepcopy(valid)
    invalid["overview_evidence"] = ["unknown.fact"]
    with pytest.raises(SummarySchemaError, match="unknown.fact"):
        parse_and_validate_summary_json(json.dumps(invalid), verbalization_facts=facts)

    wrong_scope = deepcopy(valid)
    wrong_scope["round_summaries"][0]["evidence"] = ["round.2.refinement_axiom"]
    with pytest.raises(SummarySchemaError, match=r"round\.1\."):
        parse_and_validate_summary_json(json.dumps(wrong_scope), verbalization_facts=facts)


def test_pipeline_validates_refinement_summary_and_writes_refinement_markdown(tmp_path: Path) -> None:
    report = refinement_report()
    summary = {
        "overview": "Two structural refinement rounds were applied.",
        "overview_evidence": ["refinement.applied_refinement_count"],
        "round_summaries": [
            {"round": 1, "summary": "Round one applied the candidate.", "evidence": ["round.1.refinement_axiom"]},
            {"round": 2, "summary": "Round two observed exhaustion.", "evidence": ["round.2.enumeration_after.status"]},
        ],
        "limitations": ["The search was bounded."],
    }
    verbalizer = FakeVerbalizer(summary)
    result = run_verbalization(report, verbalizer)
    assert result["report_schema"] == "modal-lens/refinement-report"
    assert result["summary"] == summary
    assert "round.1." in verbalizer.last_messages[1]["content"]

    markdown = _render_refinement_summary_markdown(summary)
    assert markdown.startswith("# Refinement Summary")
    assert "## Applied Refinement Rounds" in markdown
    assert "### Round 2" in markdown
    assert "round.2.enumeration_after.status" in markdown

    paths = write_verbalization_result(result, tmp_path / "out")
    document = json.loads(paths["summary_json"].read_text(encoding="utf-8"))
    assert document["schema"] == "modal-lens/refinement-summary"
    assert document["schema_version"] == "1.0"
    assert "# Refinement Summary" in paths["summary_markdown"].read_text(encoding="utf-8")
