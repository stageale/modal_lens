from __future__ import annotations

import json
from pathlib import Path

import pytest

from verbalization.base import GenerationResult
from verbalization.launcher import launch_verbalization_job


def _report() -> dict:
    return {
        "schema": "modal-lens/refinement-report",
        "schema_version": "1.0",
        "status": "completed",
        "stop_reason": "no_refinement_candidate",
        "applied_refinement_count": 0,
        "initial": {
            "theory_path": "/tmp/input.thy",
            "run_id": "run-0",
            "output_dir": "/tmp/run-0",
            "enumeration": {"status": "exhausted", "model_count": 0},
        },
        "iteration": [],
        "final": {
            "theory_path": "/tmp/input.thy",
            "run_id": "run-0",
            "output_dir": "/tmp/run-0",
            "enumeration": {"status": "exhausted", "model_count": 0},
        },
    }


def _request() -> dict:
    return {
        "schema": "modal-lens/verbalization-request",
        "schema_version": "1.0",
        "backend": "ollama",
        "model_id": "qwen3.5:9b",
        "report_path": "refinement.json",
        "output_directory": "output",
    }


class FakeVerbalizer:
    backend = "ollama"
    model_id = "qwen3.5:9b"

    def generate(self, _request):
        summary = {
            "overview": "No refinement was applied.",
            "overview_evidence": ["refinement.applied_refinement_count"],
            "round_summaries": [],
            "limitations": ["The bounded enumeration was exhausted."],
        }
        return GenerationResult(self.backend, self.model_id, json.dumps(summary))


def test_launcher_accepts_refinement_reports_and_preserves_backend_configuration(
    tmp_path: Path, monkeypatch
) -> None:
    (tmp_path / "refinement.json").write_text(json.dumps(_report()), encoding="utf-8")
    request_path = tmp_path / "request.json"
    request_path.write_text(json.dumps(_request()), encoding="utf-8")
    monkeypatch.setattr("verbalization.launcher.create_verbalizer", lambda **_: FakeVerbalizer())

    result = launch_verbalization_job(request_path)
    assert result["status"] == "completed"
    assert result["backend"] == "ollama"
    summary = json.loads(Path(result["artifacts"]["summary_json"]).read_text(encoding="utf-8"))
    assert summary["schema"] == "modal-lens/refinement-summary"
    assert summary["round_summaries"] == []


def test_launcher_rejects_wrong_refinement_report_version(tmp_path: Path, monkeypatch) -> None:
    report = _report()
    report["schema_version"] = "2.0"
    (tmp_path / "refinement.json").write_text(json.dumps(report), encoding="utf-8")
    request_path = tmp_path / "request.json"
    request_path.write_text(json.dumps(_request()), encoding="utf-8")
    monkeypatch.setattr("verbalization.launcher.create_verbalizer", lambda **_: FakeVerbalizer())

    with pytest.raises(ValueError, match="Unsupported refinement report schema version"):
        launch_verbalization_job(request_path)


def test_launcher_still_rejects_an_unrelated_report_schema(tmp_path: Path) -> None:
    (tmp_path / "refinement.json").write_text(
        json.dumps({"schema": "wrong", "schema_version": "1.0"}), encoding="utf-8"
    )
    request_path = tmp_path / "request.json"
    request_path.write_text(json.dumps(_request()), encoding="utf-8")

    with pytest.raises(ValueError, match="Unsupported report schema"):
        launch_verbalization_job(request_path)
