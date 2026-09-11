from __future__ import annotations

import json
from pathlib import Path

import pytest

from verbalization.base import GenerationResult
from verbalization.launcher import launch_verbalization_job, launch_verbalization_jobs


class FakeVerbalizer:
    backend = "fake"
    model_id = "fake/model"

    def __init__(self, summary: dict):
        self.summary = summary

    def generate(self, _request):
        return GenerationResult(
            backend=self.backend,
            model_id=self.model_id,
            raw_text=json.dumps(self.summary),
        )


def _request() -> dict:
    return {
        "schema": "modal-lens/verbalization-request",
        "schema_version": "1.0",
        "backend": "transformers",
        "model_id": "fake/model",
        "report_path": "report.json",
        "output_directory": "output",
        "seed": 42,
        "verbalization_mode": "grounded",
        "reasoning": False,
    }


def test_launch_verbalization_job_validates_contract_and_writes_artifacts(
    tmp_path: Path,
    monkeypatch,
    sample_report: dict,
    sample_summary: dict,
) -> None:
    (tmp_path / "report.json").write_text(
        json.dumps(sample_report),
        encoding="utf-8",
    )
    job_file = tmp_path / "request.json"
    job_file.write_text(json.dumps(_request()), encoding="utf-8")

    monkeypatch.setattr(
        "verbalization.launcher.create_verbalizer",
        lambda **_options: FakeVerbalizer(sample_summary),
    )

    result = launch_verbalization_job(job_file)

    assert result["status"] == "completed"
    assert result["backend"] == "fake"
    assert result["model_id"] == "fake/model"

    for path in result["artifacts"].values():
        assert Path(path).is_file()

    summary = json.loads(
        Path(result["artifacts"]["summary_json"]).read_text(encoding="utf-8")
    )
    assert summary["schema"] == "modal-lens/verbalization-summary"


def test_launcher_forwards_interpretive_reasoning(
    tmp_path: Path,
    monkeypatch,
    sample_report: dict,
    sample_summary: dict,
) -> None:
    (tmp_path / "report.json").write_text(
        json.dumps(sample_report),
        encoding="utf-8",
    )
    request = _request()
    request["verbalization_mode"] = "interpretive"
    request["reasoning"] = True
    request["max_new_tokens"] = 2048
    request_path = tmp_path / "request.json"
    request_path.write_text(json.dumps(request), encoding="utf-8")
    create_options = {}

    def create_fake(**options):
        create_options.update(options)
        return FakeVerbalizer(sample_summary)

    monkeypatch.setattr(
        "verbalization.launcher.create_verbalizer",
        create_fake,
    )

    result = launch_verbalization_job(request_path)

    assert create_options["reasoning"] is True
    assert result["verbalization_mode"] == "interpretive"
    assert result["reasoning"] is True

    provenance = json.loads(
        Path(result["artifacts"]["provenance"]).read_text(encoding="utf-8")
    )
    assert provenance["verbalization_mode"] == "interpretive"
    assert provenance["reasoning_enabled"] is True


@pytest.mark.parametrize(
    ("field", "value", "message"),
    [
        ("schema", "other/request", "Unsupported verbalization request schema"),
        ("schema_version", "2.0", "Unsupported verbalization request schema version"),
    ],
)
def test_launch_verbalization_job_rejects_request_contract_mismatches(
    tmp_path: Path,
    field: str,
    value: str,
    message: str,
) -> None:
    request = _request()
    request[field] = value
    job_file = tmp_path / "request.json"
    job_file.write_text(json.dumps(request), encoding="utf-8")

    with pytest.raises(ValueError, match=message):
        launch_verbalization_job(job_file)


def test_launch_verbalization_job_rejects_invalid_report_contract(
    tmp_path: Path,
) -> None:
    (tmp_path / "report.json").write_text(
        json.dumps(
            {
                "schema": "wrong",
                "schema_version": "1.0",
                "analysis": {},
                "clusters": [],
                "highlights": [],
            }
        ),
        encoding="utf-8",
    )
    job_file = tmp_path / "request.json"
    job_file.write_text(json.dumps(_request()), encoding="utf-8")

    with pytest.raises(ValueError, match="Unsupported report schema"):
        launch_verbalization_job(job_file)

def test_batch_verbalization_reuses_verbalizer(
    tmp_path,
    monkeypatch,
    sample_report,
    sample_summary,
):
    create_calls = []

    def create_fake(**options):
        create_calls.append(options)
        return FakeVerbalizer(sample_summary)

    monkeypatch.setattr(
        "verbalization.launcher.create_verbalizer",
        create_fake,
    )

    requests = []

    for cluster_id in range(2):
        directory = tmp_path / f"cluster-{cluster_id}"
        directory.mkdir()

        report_path = directory / "report.json"
        report_path.write_text(
            json.dumps(sample_report),
            encoding="utf-8",
        )

        request = _request()
        request["report_path"] = "report.json"
        request["output_directory"] = "output"

        request_path = directory / "request.json"
        request_path.write_text(
            json.dumps(request),
            encoding="utf-8",
        )

        requests.append(request_path)

    result = launch_verbalization_jobs(requests)

    assert len(create_calls) == 1
    assert len(result["jobs"]) == 2

    for job in result["jobs"]:
        assert job["status"] == "completed"

        for path in job["artifacts"].values():
            assert Path(path).is_file()
