from __future__ import annotations

import json
from collections.abc import Iterable, Mapping
from copy import deepcopy
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError

SUMMARY_SCHEMA_VERSION = "1.0"

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

def summary_json_schema() -> dict[str, Any]:
    """Return an independent copy of the summary JSON schema."""
    return deepcopy(SUMMARY_JSON_SCHEMA)

def validate_summary_schema(summary: Mapping[str, Any]) -> tuple[str, ...]:
    """Return all structural schema violations."""
    validator = Draft202012Validator(SUMMARY_JSON_SCHEMA)
    
    validation_errors = sorted(
        validator.iter_errors(summary),
        key=lambda error: (tuple(str(component) for component in error.absolute_path), error.message)
    )
    
    return tuple(_format_validation_error(error) for error in validation_errors)

def require_valid_summary_schema(summary: Mapping[str, Any]) -> None:
    """Raise when a parsed summary violates the JSON schema."""
    errors = validate_summary_schema(summary)
    
    if not errors:
        return
    
    formatted_errors = "\n".join(f"- {error}" for error in errors)
    
    raise SummarySchemaError(f"Summary violates the output schema: \n{formatted_errors}")

def parse_and_validate_summary_json(raw_text: str) -> dict[str, Any]:
    """Parse a model response and require schema compliance."""
    summary = parse_summary_json(raw_text)
    
    require_valid_summary_schema(summary)
    
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