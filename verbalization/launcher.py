from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from .factory import create_verbalizer
from .facts import REFINEMENT_REPORT_SCHEMA, SUPPORTED_REFINEMENT_REPORT_SCHEMA_VERSION
from .pipeline import run_verbalization, write_verbalization_result

VERBALIZATION_REQUEST_SCHEMA_VERSION = "1.0"
VERBALIZATION_REQUEST_SCHEMA = "modal-lens/verbalization-request"

ANALYSIS_REPORT_SCHEMA = "modal-lens/analysis-report"
ANALYSIS_REPORT_SCHEMA_VERSION = "1.1"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Launch an Axiom Refiner verbalization job.")
    
    parser.add_argument("config", nargs="+", help="Path to verbalization_request.json")
    
    arguments = parser.parse_args(argv)
    
    try:
        if len(arguments.config) == 1:
            response = launch_verbalization_job(arguments.config[0])
        else:
            response = launch_verbalization_jobs(arguments.config)
        
    except Exception as error:
        print(json.dumps({
            "status": "failed",
            "error_type": type(error).__name__,
            "error": str(error)
        }, ensure_ascii=False), file=sys.stderr)
        
        return 1
    
    print(json.dumps(response, ensure_ascii=False, sort_keys=True))
    
    return 0

def launch_verbalization_jobs(config_paths: Sequence[str | Path]) -> dict[str, Any]:
    jobs = [
        _prepare_job(config_path)
        for config_path in config_paths
    ]
    
    if not jobs:
        raise ValueError("At least one verbalization job is required.")
    
    first = jobs[0]
    
    for job in jobs[1:]:
        if job["backend"] != first["backend"] or job["model_id"] != first["model_id"] or job["backend_options"] != first["backend_options"]:
            raise ValueError("Batched verbalization jobs must use the same backend and model configuration.")
        
    verbalizer = create_verbalizer(backend=first["backend"], model_id=first["model_id"], **first["backend_options"])
    
    results = [
        _run_prepared_job(job, verbalizer)
        for job in jobs
    ]
    
    return {
        "status": "completed",
        "backend": verbalizer.backend,
        "model_id": verbalizer.model_id,
        "jobs": results
    }

def launch_verbalization_job(config_path: str | Path) -> dict[str, Any]:
    return launch_verbalization_jobs([config_path])["jobs"][0]
    

def _prepare_job(config_path: str | Path) -> dict[str, Any]:
    job_path = Path(config_path).resolve()
    
    job = _load_json_object(job_path, label="Verbalization job")
    
    _validate_job_schema(job)
    
    backend = _require_string(job, "backend")
    model_id = _require_string(job, "model_id")
    
    report_path = _resolve_path(job_path.parent, _require_string(job, "report_path"))
    
    output_directory = _resolve_path(job_path.parent, _require_string(job, "output_directory"))
    
    report = _load_json_object(report_path, label="Report")
    
    _validate_report(report)
    
    return {
        "request_path": job_path,
        "backend": backend,
        "model_id": model_id,
        "backend_options": _backend_options(job),
        "report": report,
        "output_directory": output_directory,
        "seed": job.get("seed", 42),
        "max_new_tokens": job.get("max_new_tokens", 768)
    }
    
def _validate_report(report: Mapping[str, Any]) -> None:
    """Validate the report type and version, retaining analysis checks."""
    schema = _require_string(report, "schema")
    
    if schema == ANALYSIS_REPORT_SCHEMA:
        _validate_analysis_report(report)
        return
    
    if schema != REFINEMENT_REPORT_SCHEMA:
        raise ValueError(f"Unsupported report schema: {schema!r}.")
    
    schema_version = _require_string(report, "schema_version")
    
    if schema_version != SUPPORTED_REFINEMENT_REPORT_SCHEMA_VERSION:
        raise ValueError(f"Unsupported refinement report schema version: {schema_version!r}.")
    
def _run_prepared_job(job: Mapping[str, Any], verbalizer) -> dict[str, Any]:
    result = run_verbalization(job["report"], verbalizer, seed=job["seed"], max_new_tokens=job["max_new_tokens"])
    artifact_paths = write_verbalization_result(result, job["output_directory"])
    
    return {
        "status": "completed",
        "request_path": str(job["request_path"]),
        "backend": verbalizer.backend,
        "model_id": verbalizer.model_id,
        "artifacts": {
            name: str(path.resolve())
            for name, path in artifact_paths.items()
        }
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
        raise ValueError(f"Field '{field}' must be a string.")
    
    normalized = value.strip()
    
    if not normalized:
        raise ValueError(f"Field '{field}' must not be empty.")
    
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
    schema = _require_string(job, "schema")
    schema_version = _require_string(job, "schema_version")

    if schema != VERBALIZATION_REQUEST_SCHEMA:
        raise ValueError(
            "Unsupported verbalization request schema: "
            f"{schema!r}."
        )

    if schema_version != VERBALIZATION_REQUEST_SCHEMA_VERSION:
        raise ValueError(
            "Unsupported verbalization request schema version: "
            f"{schema_version!r}."
        )
        
def _validate_analysis_report(report: Mapping[str, Any]) -> None:
    schema = _require_string(report, "schema")
    schema_version = _require_string(report, "schema_version")
    
    if schema != ANALYSIS_REPORT_SCHEMA:
        raise ValueError(f"Unsupported analysis report schema: {schema!r}.")
    
    if schema_version != ANALYSIS_REPORT_SCHEMA_VERSION:
        raise ValueError(f"Unsupported analysis report schema version: {schema_version!r}")

    analysis = report.get("analysis")
    clusters = report.get("clusters")
    highlights = report.get("highlights")
    
    if not isinstance(analysis, Mapping):
        raise ValueError("Analysis report field 'analysis' must be a JSON object.")
    
    if not isinstance(clusters, list):
        raise ValueError("Analysis report field 'clusters' must be a JSON array.")
    
    if not isinstance(highlights, list):
        raise ValueError("Analysis report field 'highlights' must be a JSON array.")

if __name__ == "__main__":
    raise SystemExit(main())