from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from .factory import create_verbalizer
from .pipeline import run_verbalization, write_verbalization_result

VERBALIZATION_JOB_SCHEMA_VERSION = "1.0"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Launch an Axiom Refiner verbalization job.")
    
    parser.add_argument("config", help="Path to verbalization_request.json")
    
    arguments = parser.parse_args(argv)
    
    try:
        response = launch_verbalization_job(arguments.config)
        
    except Exception as error:
        print(json.dumps({
            "status": "failed",
            "error_type": type(error).__name__,
            "error": str(error)
        }, ensure_ascii=False), file=sys.stderr)
        
        return 1
    
    print(json.dumps(response, ensure_ascii=False, sort_keys=True))
    
    return 0

def launch_verbalization_job(config_path: str | Path) -> dict[str, Any]:
    job_path = Path(config_path).resolve()
    
    job = _load_json_object(job_path, label="Verbalization job")
    
    _validate_job_schema(job)
    
    backend = _require_string(job, "backend")
    
    model_id = _require_string(job, "model_id")
    
    report_path = _resolve_path(job_path.parent, _require_string(job, "report_path"))
    
    output_directory = _resolve_path(job_path.parent, _require_string(job, "output_directory"))
        
    report = _load_json_object(report_path, label="Analysis report")
    
    seed = job.get("seed", 42)
    max_new_tokens = job.get("max_new_tokens", 768)
    
    verbalizer = create_verbalizer(
        backend=backend,
        model_id=model_id,
        **_backend_options(job)
    )
    
    result = run_verbalization(
        report,
        verbalizer,
        seed=seed,
        max_new_tokens=max_new_tokens
    )
    
    artifact_paths = write_verbalization_result(result, output_directory)
    
    return {
        "status": "completed",
        "backend": verbalizer.backend,
        "model_id": verbalizer.model_id,
        "artifacts": {name: str(path.resolve()) for name, path in artifact_paths.items()}
    }


def _load_json_object(path: str | Path, *, label: str) -> dict[str, Any]:
    json_path = Path(path)
    
    try:
        content = json_path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"Could not read {label}: {json_path}") from error
    
    try:
        value = json.loads(content)
    except json.JSONDecodeError as error:
        raise ValueError(f"{label} is not valid JSON: {json_path}") from error
    
    if not isinstance(value, dict):
        raise ValueError(f"{label} must contain a JSON object.")
    
    return value
    
def _require_string(source: Mapping[str, Any], field: str) -> str:
    value = source.get(field)
    
    if not isinstance(value, str):
        raise ValueError(f"Job field '{field}' must be a string.")
    
    normalized = value.strip()
    
    if not normalized:
        raise ValueError(f"Job field '{field}' must not be empty.")
    
    return normalized

def _resolve_path(base_directory: Path, value: str) -> Path:
    path = Path(value).expanduser()
    
    if path.is_absolute():
        return path
    
    return base_directory / path

def _backend_options(job: Mapping[str, Any]) -> dict[str, Any]:
    value = job.get("backend_options", {})
    
    if not isinstance(value, Mapping):
        raise ValueError("Job field 'backend_options' must be a JSON object.")
    
    return dict(value)

def _validate_job_schema(job: Mapping[str, Any]) -> None:
    schema_version = _require_string(job, "schema_version")
    
    if schema_version != VERBALIZATION_JOB_SCHEMA_VERSION:
        raise ValueError(f"Unsupported verbalization job schema version: {schema_version!r}.")
    

if __name__ == "__main__":
    raise SystemExit(main())