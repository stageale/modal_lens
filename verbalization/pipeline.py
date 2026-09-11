from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from .base import GenerationRequest, Verbalizer
from .facts import REFINEMENT_REPORT_SCHEMA, build_verbalization_facts, verbalization_facts_sha256
from .prompt import build_verbalization_messages
from .summary_schema import REFINEMENT_SUMMARY_SCHEMA_VERSION, SummarySchemaError, parse_and_validate_summary_json


VERBALIZATION_SUMMARY_SCHEMA = "modal-lens/verbalization-summary"
VERBALIZATION_SUMMARY_SCHEMA_VERSION = "1.0"
VERBALIZATION_PROVENANCE_SCHEMA = "modal-lens/verbalization-provenance"
VERBALIZATION_PROVENANCE_SCHEMA_VERSION = "1.0"
REFINEMENT_SUMMARY_SCHEMA = "modal-lens/refinement-summary"


def write_verbalization_result(result: Mapping[str, Any], output_directory: str | Path) -> dict[str, Path]:
    output_path = Path(output_directory)

    output_path.mkdir(parents=True, exist_ok=True)

    raw_output_path = output_path / "raw_output.txt"


    summary_json_path = output_path / "summary.json"


    summary_markdown_path = output_path / "summary.md"

    provenance_path = output_path / "provenance.json"

    raw_output_path.write_text(str(result["raw_output"]), encoding="utf-8")

    summary = result["summary"]
    is_refinement = result.get("report_schema") == REFINEMENT_REPORT_SCHEMA
    
    summary_document = {
        **summary,
        "schema": REFINEMENT_SUMMARY_SCHEMA if is_refinement else VERBALIZATION_SUMMARY_SCHEMA,
        "schema_version": REFINEMENT_SUMMARY_SCHEMA_VERSION if is_refinement else VERBALIZATION_SUMMARY_SCHEMA_VERSION
    }

    summary_json_path.write_text(
        json.dumps(summary_document, ensure_ascii=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8"
    )

    summary_markdown = _render_refinement_summary_markdown(summary) if is_refinement else _render_summary_markdown(summary)

    summary_markdown_path.write_text(summary_markdown, encoding="utf-8")

    provenance = result["provenance"]
    
    if not isinstance(provenance, Mapping):
        raise ValueError("Verbalization provenance must be a mapping.")

    provenance_document = {
        **provenance,
        "schema": VERBALIZATION_PROVENANCE_SCHEMA,
        "schema_version": VERBALIZATION_PROVENANCE_SCHEMA_VERSION
    }

    provenance_path.write_text(
        json.dumps(provenance_document, ensure_ascii=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8"
    )

    artifact_paths = {
        "raw_output": raw_output_path,
        "summary_json": summary_json_path,
        "summary_markdown": summary_markdown_path,
        "provenance": provenance_path,
    }

    if "invalid_raw_output" in result:
        invalid_raw_output_path = (output_path / "raw_output.invalid-attempt-1.txt")

        invalid_raw_output_path.write_text(str(result["invalid_raw_output"]), encoding="utf-8",)

        artifact_paths["invalid_raw_output"] = (invalid_raw_output_path)

    return artifact_paths

def run_verbalization(
        report: Mapping[str, Any],
        verbalizer: Verbalizer,
        *,
        seed: int = 42,
        max_new_tokens: int = 768,
        verbalization_mode: str = "grounded",
        reasoning: bool = False,
    ) -> dict[str, Any]:
    if not isinstance(reasoning, bool):
        raise ValueError("reasoning must be a boolean.")

    verbalization_facts = build_verbalization_facts(report, verbalization_mode=verbalization_mode)

    normalized_mode = verbalization_facts["source"]["verbalization_mode"]

    messages = build_verbalization_messages(verbalization_facts, verbalization_mode=normalized_mode)

    request = GenerationRequest(messages=messages, seed=seed, max_new_tokens=max_new_tokens)

    generation = verbalizer.generate(request)

    attempt_records: list[dict[str, Any]] = [
        {
            "attempt": 1,
            "messages_sha256": _messages_sha256(request.messages),
            "raw_output_sha256": _sha256_text(generation.raw_text)
        }
    ]

    invalid_raw_output: str | None = None
    try:
        summary = parse_and_validate_summary_json(generation.raw_text, verbalization_facts=verbalization_facts)
    except SummarySchemaError as error:
        invalid_raw_output = generation.raw_text
        attempt_records[0]["validation_error"] = str(error)

        correction_messages = _schema_correction_messages(
            messages,
            invalid_raw_output=generation.raw_text,
            schema_error=error,
            verbalization_facts=verbalization_facts
        )

        correction_request = GenerationRequest(
            messages=correction_messages,
            seed=seed,
            max_new_tokens=max_new_tokens
        )

        generation = verbalizer.generate(correction_request)

        attempt_records.append(
            {
                "attempt": 2,
                "messages_sha256": _messages_sha256(correction_request.messages),
                "raw_output_sha256": _sha256_text(generation.raw_text)
            }
        )

        summary = parse_and_validate_summary_json(generation.raw_text, verbalization_facts=verbalization_facts)

    result: dict[str, Any] = {
        "report_schema": report.get("schema"),
        "summary": summary,
        "raw_output": generation.raw_text,
        "provenance": {
            "backend": generation.backend,
            "model_id": generation.model_id,
            "seed": seed,
            "max_new_tokens": max_new_tokens,
            "verbalization_mode": normalized_mode,
            "reasoning_enabled": reasoning,
            "verbalization_facts_sha256": verbalization_facts_sha256(verbalization_facts),
            "messages_sha256": _messages_sha256(messages),
            "raw_output_sha256": _sha256_text(generation.raw_text),
            "backend_metadata": dict(generation.metadata),
            "schema_correction": {
                "applied": invalid_raw_output is not None,
                "attempt_count": len(attempt_records),
                "attempts": attempt_records,
            }
        }
    }

    if invalid_raw_output is not None:
        result["invalid_raw_output"] = invalid_raw_output

    return result

def _schema_correction_messages(
        original_messages: tuple[Mapping[str, str], ...],
        *,
        invalid_raw_output: str,
        schema_error: SummarySchemaError,
        verbalization_facts: Mapping[str, Any],
    ) -> tuple[Mapping[str, str], ...]:
    """Request one bounded correction of a schema-invalid response."""
    evidence_ids = sorted(
        str(fact["id"])
        for fact in verbalization_facts["facts"]
    )

    correction_message = f"""
    Your previous JSON response failed validation:

    {schema_error}

    Return one corrected JSON object that satisfies the original output contract.
    Preserve the substantive explanation unless a schema correction requires a
    change.

    Every required evidence array must be non-empty and may contain only exact
    identifiers from the list below. Do not invent identifiers.

    For a cluster summary with cluster_id N, prefer identifiers beginning with
    "cluster.N.". For a refinement round N, use only identifiers beginning with
    "round.N.".

    Return no Markdown, reasoning trace, or text outside the corrected JSON object.

    ALLOWED EVIDENCE IDENTIFIERS:

    {json.dumps(evidence_ids, ensure_ascii=False, indent=2)}
        """.strip()

    return (
        *original_messages,
        {
            "role": "assistant",
            "content": invalid_raw_output,
        },
        {
            "role": "user",
            "content": correction_message,
        },
    )

def _render_refinement_summary_markdown(summary: Mapping[str, Any]) -> str:
    """Render a refinement overview and its applied rounds with evidence."""
    lines = [
        "# Refinement Summary",
        "",
        str(summary["overview"]),
        "",
        "**Evidence:**",
        ""
    ]
    
    lines.extend(f"- `{identifier}`" for identifier in summary["overview_evidence"])
    
    lines.extend(["", "## Applied Refinement Rounds", ""])
    
    if not summary["round_summaries"]:
        lines.extend(["No refinement rounds were applied.", ""])
        
    for entry in summary["round_summaries"]:
        lines.extend(
            [
                f"### Round {int(entry['round'])}",
                "",
                str(entry["summary"]),
                "",
                "**Evidence:**",
                ""
            ]
        )
        
        lines.extend(f"- `{identifier}`" for identifier in entry["evidence"])
        lines.append("")
        
    lines.extend(["## Limitations", ""])
    lines.extend(f"- {limitation}" for limitation in summary["limitations"])
    lines.append("")
    
    return "\n".join(lines)

def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def _messages_sha256(messages: tuple[Mapping[str, str], ...]) -> str:
    serialized = json.dumps(messages, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return _sha256_text(serialized)

def _render_summary_markdown(
    summary: Mapping[str, Any],
) -> str:
    lines = [
        "# Analysis Summary",
        "",
        str(summary["overview"]),
        "",
        "## Clusters",
        "",
    ]

    for cluster in summary["cluster_summaries"]:
        cluster_id = cluster["cluster_id"]

        lines.extend(
            [
                f"### Cluster {cluster_id}",
                "",
                str(cluster["summary"]),
                "",
                "**Evidence:**",
                "",
            ]
        )

        for evidence in cluster["evidence"]:
            lines.append(
                f"- `{evidence}`"
            )

        lines.append("")

    lines.extend(
        [
            "## Limitations",
            "",
        ]
    )

    for limitation in summary["limitations"]:
        lines.append(
            f"- {limitation}"
        )

    lines.append("")

    return "\n".join(lines)