from __future__ import annotations

import json

import pytest

from verbalization.summary_schema import (
    SummaryParseError,
    SummarySchemaError,
    parse_and_validate_summary_json,
    parse_summary_json,
    require_valid_summary_schema,
    summary_json_schema,
    validate_summary_schema,
)


def test_parse_and_validate_accepts_plain_and_fenced_json(sample_summary: dict) -> None:
    raw = json.dumps(sample_summary)
    assert parse_and_validate_summary_json(raw) == sample_summary
    assert parse_and_validate_summary_json(f"```json\n{raw}\n```") == sample_summary


@pytest.mark.parametrize(
    ("raw", "message"),
    [
        ("", "empty"),
        ("not json", "not valid JSON"),
        ("[]", "one JSON object"),
    ],
)
def test_parse_summary_json_rejects_invalid_outputs(raw: str, message: str) -> None:
    with pytest.raises(SummaryParseError, match=message):
        parse_summary_json(raw)


def test_parse_summary_json_rejects_non_string_input() -> None:
    with pytest.raises(TypeError, match="must be a string"):
        parse_summary_json({})  # type: ignore[arg-type]


def test_schema_rejects_missing_and_extra_fields(sample_summary: dict) -> None:
    missing = dict(sample_summary)
    del missing["limitations"]
    errors = validate_summary_schema(missing)
    assert any("limitations" in error for error in errors)

    extra = dict(sample_summary)
    extra["invented"] = True
    with pytest.raises(SummarySchemaError, match="Additional properties"):
        require_valid_summary_schema(extra)


def test_schema_rejects_invalid_pattern_ids_and_duplicate_evidence(
    sample_summary: dict,
) -> None:
    invalid = json.loads(json.dumps(sample_summary))
    invalid["cluster_summaries"][0]["notable_patterns"] = ["pattern-1"]
    invalid["cluster_summaries"][0]["evidence"] = ["same", "same"]

    errors = validate_summary_schema(invalid)
    assert any("notable_patterns" in error for error in errors)
    assert any("non-unique" in error for error in errors)


def test_summary_json_schema_returns_an_independent_copy() -> None:
    first = summary_json_schema()
    second = summary_json_schema()
    first["title"] = "changed"
    assert second["title"] == "LoDEx Verbalization Summary"
