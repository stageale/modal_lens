from __future__ import annotations

import hashlib
import json
from copy import deepcopy
from pathlib import Path

import pytest

from verbalization.base import GenerationRequest, GenerationResult, Verbalizer
from verbalization.pipeline import (
    _messages_sha256,
    _render_summary_markdown,
    _sha256_text,
    run_verbalization,
    write_verbalization_result,
)
from verbalization.summary_schema import SummarySchemaError


class FakeVerbalizer(Verbalizer):
    def __init__(self, raw_text: str):
        self.raw_text = raw_text
        self.last_request: GenerationRequest | None = None

    @property
    def backend(self) -> str:
        return "fake"

    @property
    def model_id(self) -> str:
        return "fake/model"

    def generate(self, request: GenerationRequest) -> GenerationResult:
        self.last_request = request
        return GenerationResult(
            backend=self.backend,
            model_id=self.model_id,
            raw_text=self.raw_text,
            metadata={"device": "test"},
        )


class SequencedFakeVerbalizer(FakeVerbalizer):
    def __init__(self, raw_texts: list[str]):
        super().__init__(raw_texts[0])
        self.raw_texts = raw_texts
        self.requests: list[GenerationRequest] = []

    def generate(self, request: GenerationRequest) -> GenerationResult:
        self.requests.append(request)
        self.last_request = request
        raw_text = self.raw_texts[len(self.requests) - 1]

        return GenerationResult(
            backend=self.backend,
            model_id=self.model_id,
            raw_text=raw_text,
            metadata={"device": "test"},
        )


def test_sha256_text_hashes_utf8_text() -> None:
    assert _sha256_text("LoDEx") == hashlib.sha256(
        "LoDEx".encode("utf-8")
    ).hexdigest()


def test_messages_sha256_is_independent_of_mapping_key_order() -> None:
    first = ({"role": "user", "content": "Example"},)
    second = ({"content": "Example", "role": "user"},)
    assert _messages_sha256(first) == _messages_sha256(second)


def test_render_summary_markdown_contains_clusters_and_evidence(
    sample_summary: dict,
) -> None:
    markdown = _render_summary_markdown(sample_summary)
    assert markdown.startswith("# Analysis Summary")
    assert "### Cluster 0" in markdown
    assert "- `cluster.0.model_count`" in markdown
    assert "## Limitations" in markdown


def test_run_verbalization_connects_facts_prompt_and_backend(
    sample_report: dict,
    sample_summary: dict,
) -> None:
    raw_text = json.dumps(sample_summary)
    verbalizer = FakeVerbalizer(raw_text)

    result = run_verbalization(
        sample_report,
        verbalizer,
        seed=17,
        max_new_tokens=256,
    )

    assert result["summary"] == sample_summary
    assert result["raw_output"] == raw_text
    assert result["provenance"]["backend"] == "fake"
    assert result["provenance"]["model_id"] == "fake/model"
    assert result["provenance"]["seed"] == 17
    assert result["provenance"]["max_new_tokens"] == 256
    assert result["provenance"]["verbalization_mode"] == "grounded"
    assert result["provenance"]["reasoning_enabled"] is False
    assert result["provenance"]["backend_metadata"] == {"device": "test"}
    assert len(result["provenance"]["messages_sha256"]) == 64
    assert len(result["provenance"]["verbalization_facts_sha256"]) == 64
    assert result["provenance"]["raw_output_sha256"] == _sha256_text(raw_text)
    assert verbalizer.last_request is not None
    assert verbalizer.last_request.seed == 17
    assert verbalizer.last_request.max_new_tokens == 256
    assert verbalizer.last_request.messages[0]["role"] == "system"


def test_run_verbalization_records_interpretive_reasoning(
    sample_report: dict,
    sample_summary: dict,
) -> None:
    verbalizer = FakeVerbalizer(json.dumps(sample_summary))

    result = run_verbalization(
        sample_report,
        verbalizer,
        verbalization_mode="interpretive",
        reasoning=True,
    )

    assert result["provenance"]["verbalization_mode"] == "interpretive"
    assert result["provenance"]["reasoning_enabled"] is True
    assert verbalizer.last_request is not None
    assert "theory.content" in verbalizer.last_request.messages[1]["content"]


def test_run_verbalization_rejects_non_boolean_reasoning(
    sample_report: dict,
    sample_summary: dict,
) -> None:
    verbalizer = FakeVerbalizer(json.dumps(sample_summary))

    with pytest.raises(ValueError, match="reasoning must be a boolean"):
        run_verbalization(
            sample_report,
            verbalizer,
            reasoning="on",  # type: ignore[arg-type]
        )


def test_run_verbalization_rejects_invalid_model_output(sample_report: dict) -> None:
    verbalizer = FakeVerbalizer("not json")

    with pytest.raises(ValueError, match="not valid JSON"):
        run_verbalization(sample_report, verbalizer)


def test_run_verbalization_corrects_one_schema_invalid_response(
    sample_report: dict,
    sample_summary: dict,
) -> None:
    invalid_summary = deepcopy(sample_summary)
    invalid_summary["cluster_summaries"][0]["evidence"] = []
    invalid_raw_output = json.dumps(invalid_summary)
    corrected_raw_output = json.dumps(sample_summary)
    verbalizer = SequencedFakeVerbalizer(
        [invalid_raw_output, corrected_raw_output]
    )

    result = run_verbalization(sample_report, verbalizer)

    assert result["summary"] == sample_summary
    assert result["raw_output"] == corrected_raw_output
    assert result["invalid_raw_output"] == invalid_raw_output

    correction = result["provenance"]["schema_correction"]
    assert correction["applied"] is True
    assert correction["attempt_count"] == 2
    assert "should be non-empty" in (
        correction["attempts"][0]["validation_error"]
    )

    assert len(verbalizer.requests) == 2
    correction_messages = verbalizer.requests[1].messages
    assert correction_messages[-2] == {
        "role": "assistant",
        "content": invalid_raw_output,
    }
    assert "cluster.0.model_count" in correction_messages[-1]["content"]


def test_run_verbalization_attempts_schema_correction_only_once(
    sample_report: dict,
    sample_summary: dict,
) -> None:
    invalid_summary = deepcopy(sample_summary)
    invalid_summary["cluster_summaries"][0]["evidence"] = []
    invalid_raw_output = json.dumps(invalid_summary)
    verbalizer = SequencedFakeVerbalizer(
        [invalid_raw_output, invalid_raw_output]
    )

    with pytest.raises(SummarySchemaError, match="should be non-empty"):
        run_verbalization(sample_report, verbalizer)

    assert len(verbalizer.requests) == 2


def test_write_verbalization_result_creates_versioned_artifacts(
    tmp_path: Path,
    sample_summary: dict,
) -> None:
    result = {
        "summary": sample_summary,
        "raw_output": json.dumps(sample_summary),
        "provenance": {
            "backend": "fake",
            "model_id": "fake/model",
        },
    }

    paths = write_verbalization_result(result, tmp_path / "verbalization")

    assert set(paths) == {
        "raw_output",
        "summary_json",
        "summary_markdown",
        "provenance",
    }
    assert paths["raw_output"].read_text(encoding="utf-8") == result["raw_output"]

    summary_document = json.loads(paths["summary_json"].read_text(encoding="utf-8"))
    assert summary_document["schema"] == "modal-lens/verbalization-summary"
    assert summary_document["schema_version"] == "1.0"
    assert summary_document["overview"] == sample_summary["overview"]
    assert summary_document["cluster_summaries"] == sample_summary["cluster_summaries"]

    provenance_document = json.loads(
        paths["provenance"].read_text(encoding="utf-8")
    )
    assert provenance_document["schema"] == "modal-lens/verbalization-provenance"
    assert provenance_document["schema_version"] == "1.0"
    assert provenance_document["backend"] == "fake"

    assert "# Analysis Summary" in paths["summary_markdown"].read_text(
        encoding="utf-8"
    )


def test_write_verbalization_result_rejects_non_mapping_provenance(
    tmp_path: Path,
    sample_summary: dict,
) -> None:
    with pytest.raises(ValueError, match="provenance must be a mapping"):
        write_verbalization_result(
            {
                "summary": sample_summary,
                "raw_output": "{}",
                "provenance": [],
            },
            tmp_path,
        )


def test_write_verbalization_result_preserves_invalid_first_attempt(
    tmp_path: Path,
    sample_summary: dict,
) -> None:
    result = {
        "summary": sample_summary,
        "raw_output": json.dumps(sample_summary),
        "invalid_raw_output": '{"evidence": []}',
        "provenance": {
            "backend": "fake",
            "model_id": "fake/model",
        },
    }

    paths = write_verbalization_result(result, tmp_path / "verbalization")

    assert paths["invalid_raw_output"].name == (
        "raw_output.invalid-attempt-1.txt"
    )
    assert paths["invalid_raw_output"].read_text(
        encoding="utf-8"
    ) == result["invalid_raw_output"]
