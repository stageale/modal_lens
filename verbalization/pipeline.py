from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from .base import GenerationRequest, Verbalizer
from .facts import build_verbalization_facts, verbalization_facts_sha256
from .prompt import build_verbalization_messages


def write_verbalization_result(result: Mapping[str, Any], output_directory: str | Path) -> dict[str, Path]:
    output_path = Path(output_directory)

    output_path.mkdir(parents=True, exist_ok=True)

    raw_output_path = output_path / "raw_output.txt"


    summary_json_path = output_path / "summary.json"


    summary_markdown_path = output_path / "summary.md"

    provenance_path = output_path / "provenance.json"

    raw_output_path.write_text(str(result["raw_output"]), encoding="utf-8")

    summary_json_path.write_text(
        json.dumps(
            result["summary"],
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8"
    )

    summary_markdown_path.write_text(
        _render_summary_markdown(result["summary"]),
        encoding="utf-8"
    )

    provenance_path.write_text(
        json.dumps(
            result["provenance"],
            ensure_ascii=False,
            indent=2,
            sort_keys=True
        )
        + "\n",
        encoding="utf-8"
    )

    return {
        "raw_output": raw_output_path,
        "summary_json": summary_json_path,
        "summary_markdown": summary_markdown_path,
        "provenance": provenance_path
    }

def run_verbalization(report: Mapping[str, Any], verbalizer: Verbalizer, *, seed: int = 42, max_new_tokens: int = 768) -> dict[str, Any]:
    verbalization_facts = (build_verbalization_facts(report))

    messages = build_verbalization_messages(verbalization_facts)
    

    request = GenerationRequest(
        messages=messages,
        seed=seed,
        max_new_tokens=max_new_tokens
    )

    generation = verbalizer.generate(request)

    summary = _parse_summary(generation.raw_text)

    return {
        "summary": summary,
        "raw_output": generation.raw_text,
        "provenance": {
            "backend": generation.backend,
            "model_id": generation.model_id,
            "seed": seed,
            "max_new_tokens": max_new_tokens,
            "verbalization_facts_sha256": verbalization_facts_sha256(verbalization_facts),
            "messages_sha256": _messages_sha256(messages),
            "raw_output_sha256": _sha256_text(generation.raw_text),
            "backend_metadata": dict(generation.metadata)
        }
    }

def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def _messages_sha256(messages: tuple[Mapping[str, str], ...]) -> str:
    serialized = json.dumps(messages, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return _sha256_text(serialized)

def _parse_summary(raw_text: str) -> dict[str, Any]:
    try:
        summary = json.loads(raw_text.strip())
    except json.JSONDecodeError as error:
        raise ValueError("Model response is not valid JSON.") from error
    
    if not isinstance(summary, dict):
        raise ValueError("Model response must be a JSON object.")
    
    required_fields = {
        "overview",
        "cluster_summaries",
        "limitations"
    }
    
    missing_fields = required_fields - summary.keys()
    
    if missing_fields:
        raise ValueError("Model response is missing fields: " + ", ".join(sorted(missing_fields)))
    
    return summary

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