import json
from pathlib import Path

from verbalization.base import GenerationResult
from verbalization.launcher import launch_verbalization_job


class FakeVerbalizer:
    backend = "fake"
    model_id = "fake/model"

    def __init__(self, summary):
        self.summary = summary

    def generate(self, _request):
        return GenerationResult(
            backend=self.backend,
            model_id=self.model_id,
            raw_text=json.dumps(self.summary),
        )


def test_launch_verbalization_job_writes_artifacts(
    tmp_path,
    monkeypatch,
    sample_report,
    sample_summary,
):
    report_file = tmp_path / "report.json"
    report_file.write_text(
        json.dumps(sample_report),
        encoding="utf-8",
    )

    job_file = tmp_path / "request.json"
    job_file.write_text(
        json.dumps(
            {
                "schema_version": "1.0",
                "backend": "transformers",
                "model_id": "fake/model",
                "report_path": "report.json",
                "output_directory": "output",
                "seed": 42,
            }
        ),
        encoding="utf-8",
    )

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