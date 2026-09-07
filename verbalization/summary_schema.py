from __future__ import annotations

import json
from collections.abc import Iterable, Mapping
from copy import deepcopy
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError

from .facts import REFINEMENT_REPORT_SCHEMA

SUMMARY_SCHEMA_VERSION = "1.0"
REFINEMENT_SUMMARY_SCHEMA_VERSION = "1.0"

class SummaryParseError(ValueError):
    """Raised when a raw model respons is not valid JSON."""
    
class SummarySchemaError(ValueError):
    """Raised when parsed JSON violates the summary schema."""
    
SUMMARY_JSON_SCHEMA: dict[str, Any] = {
    "$schema": (
        "https://json-schema.org/"
        "draft/2020-12/schema"
    ),
    "title": "LoDEx Verbalization Summary",
    "type": "object",
    "additionalProperties": False,
    "required": [
        "overview",
        "cluster_summaries",
        "limitations",
    ],
    "properties": {
        "overview": {
            "type": "string",
            "minLength": 1,
        },
        "cluster_summaries": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": [
                    "cluster_id",
                    "summary",
                    "notable_patterns",
                    "evidence",
                ],
                "properties": {
                    "cluster_id": {
                        "type": "integer",
                        "minimum": 0,
                    },
                    "summary": {
                        "type": "string",
                        "minLength": 1,
                    },
                    "notable_patterns": {
                        "type": "array",
                        "uniqueItems": True,
                        "items": {
                            "type": "string",
                            "pattern": (
                                "^cluster-[0-9]+"
                                "-pattern-[0-9]+$"
                            ),
                        },
                    },
                    "evidence": {
                        "type": "array",
                        "minItems": 1,
                        "uniqueItems": True,
                        "items": {
                            "type": "string",
                            "minLength": 1,
                        },
                    },
                },
            },
        },
        "limitations": {
            "type": "array",
            "uniqueItems": True,
            "items": {
                "type": "string",
                "minLength": 1,
            },
        },
    },
}
REFINEMENT_SUMMARY_JSON_SCHEMA: dict[str, Any] = {
    "$schema": SUMMARY_JSON_SCHEMA["$schema"],
    "title": "ModalLens Refinement Summary",
    "type": "object",
    "additionalProperties": False,
    "required": [
        "overview",
        "overview_evidence",
        "round_summaries",
        "limitations"
    ],
    "$defs": {
        "evidence": {
            "type": "array",
            "minItems": 1,
            "uniqueItems": True,
            "items": {"type": "string", "minLength": 1}
        },
    },
    "properties": {
        "overview": {"type": "string", "minLength": 1},
        "overview_evidence": {"$ref": "#/$defs/evidence"},
        "round_summaries": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["round", "summary", "evidence"],
                "properties": {
                    "round": {"type": "integer", "minimum": 1},
                    "summary": {"type": "string", "minLength": 1},
                    "evidence": {"$ref": "#/$defs/evidence"}
                }
            }
        },
        "limitations": {
            "type": "array",
            "uniqueItems": True,
            "items": {"type": "string", "minLength": 1}
        }
    }
}

def summary_json_schema(*, verbalization_facts: Mapping[str, Any] | None = None) -> dict[str, Any]:
    """Return an independent summary schema for the supplied facts."""
    
    if (
        verbalization_facts is not None
        and verbalization_facts["source"].get("report_schema") == REFINEMENT_REPORT_SCHEMA
    ):
        schema = REFINEMENT_SUMMARY_JSON_SCHEMA
    return deepcopy(schema)

def validate_summary_schema(summary: Mapping[str, Any], *, verbalization_facts: Mapping[str, Any] | None = None) -> tuple[str, ...]:
    """Return structural violations and applicable refinement errors."""
    validator = Draft202012Validator(summary_json_schema(verbalization_facts=verbalization_facts))
    
    validation_errors = sorted(
        validator.iter_errors(summary),
        key=lambda error: (tuple(str(component) for component in error.absolute_path), error.message)
    )
    
    errors = tuple(_format_validation_error(error) for error in validation_errors)
    
    if errors or verbalization_facts is None:
        return errors
    
    if (
        verbalization_facts["source"].get("report_schema") == REFINEMENT_REPORT_SCHEMA
    ):
        return _validate_refinement_evidence(summary, verbalization_facts)
    
    return ()

def require_valid_summary_schema(summary: Mapping[str, Any], *, verbalization_facts: Mapping[str, Any] | None = None) -> None:
    """Raise when a parsed summary structure or refinement references are invalid."""
    errors = validate_summary_schema(summary, verbalization_facts=verbalization_facts)
    
    if not errors:
        return
    
    formatted_errors = "\n".join(f"- {error}" for error in errors)
    
    raise SummarySchemaError(f"Summary violates the output schema: \n{formatted_errors}")

def parse_and_validate_summary_json(raw_text: str, *, verbalization_facts: Mapping[str, Any] | None = None) -> dict[str, Any]:
    """Parse a response and validate its structure and supplied references."""
    summary = parse_summary_json(raw_text)
    
    require_valid_summary_schema(summary, verbalization_facts=verbalization_facts)
    
    return summary

def parse_summary_json(raw_text: str) -> dict[str, Any]:
    """Parse a raw model response as one JSON object."""
    if not isinstance(raw_text, str):
        raise TypeError("Raw summary output must be a string.")
    
    text = _strip_single_json_fence(raw_text)
    
    if not text:
        raise SummaryParseError("Model response is empty")
    
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as error:
        raise SummaryParseError(f"Model response is not valid JSON: {error.msg} at line {error.lineno}, column {error.colno}.") from error
    
    if not isinstance(parsed, dict):
        raise SummaryParseError("Model response must be one JSON object.")
    
    return parsed

def _strip_single_json_fence(raw_text: str) -> str:
    text = raw_text.strip()
    
    if not text.startswith("```"):
        return text
    
    lines = text.splitlines()
    
    if len(lines) < 3:
        return text
    
    opening_fence = lines[0].strip()
    closing_fence = lines[-1].strip()
    
    if opening_fence not in {"```", "```json", "```JSON"}:
        return text
    
    if closing_fence != "```":
        return text
    
    return "\n".join(lines[1:-1]).strip()

def _json_path(path: Iterable[str | int]) -> str:
    result = "$"
    
    for component in path:
        if isinstance(component, int):
            result += f"[{component}]"
        else:
            result += f".{component}"
            
    return result

def _format_validation_error(error: ValidationError) -> str:
    path = _json_path(error.absolute_path)
    
    return f"{path}: {error.message}"

def _validate_refinement_evidence(summary: Mapping[str, Any], verbalization_facts: Mapping[str, Any]) -> tuple[str, ...]:
    """Check round coverage and evidence references after schema validation."""
    facts = verbalization_facts["facts"]
    known_ids = {fact["id"] for fact in facts}
    
    expected_rounds = sorted(
        fact["value"]
        for fact in facts
        if fact["id"].startswith("round.")
        and fact["id"].endswith(".round")
    )
    actual_rounds = [
        entry["round"] for entry in summary["round_summaries"]
    ]
    
    errors: list[str] = []
    
    if actual_rounds != expected_rounds:
        errors.append(
            "$.round_summaries: Expected each supplied round exactly once "
            f"in ascending order: {expected_rounds!r}; got {actual_rounds!r}."
        )
        
    groups: list[tuple[str, list[str], str | None]] = [
        ("$.overview_evidence", summary["overview_evidence"], None)
    ]
    
    for index, entry in enumerate(summary["round_summaries"]):
        groups.append(
            (
                f"$.round_summaries[{index}].evidence",
                entry["evidence"],
                f"round.{int(entry['round'])}."
            )
        )
        
    for path, identifiers, required_prefix in groups:
        for index, identifier in enumerate(identifiers):
            if identifier not in known_ids:
                errors.append(
                    f"{path}[{index}]: Unknown fact identifier {identifier!r}."
                )
            elif (
                required_prefix is not None
                and not identifier.startswith(required_prefix)
            ):
                errors.append(
                    f"{path}[{index}]: Evidence must belong to "
                    f"{required_prefix!r}; got {identifier!r}."
                )
    return tuple(errors)