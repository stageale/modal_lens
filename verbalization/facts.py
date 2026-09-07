from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping, Sequence
from copy import deepcopy
from typing import Any 

VERBALIZATION_FACTS_SCHEMA_VERSION = "1.0"
SUPPORTED_REPORT_SCHEMA_VERSION = "1.1"


def build_verbalization_facts(report: Mapping[str, Any]) -> dict[str, Any]:
    """Build a deterministic, backend-independent fact collection.
    
    The result contains only information already present in the analysis report. It excludes volatile metadata
    and unrestricted theory text.

    Args:
        report (Mapping[str, Any]): JSON-like data object

    Returns:
        dict[str, Any]: analysis report for language model
    """
    if not isinstance(report, Mapping):
        raise TypeError("Report must be a mapping.")
    
    report_schema_version = _require_field(report, "schema_version", path="")
    
    if report_schema_version != SUPPORTED_REPORT_SCHEMA_VERSION:
        raise ValueError(f"Unsupported report schema version: {report_schema_version!r}.")
    
    scope = _require_mapping(_require_field(report, "scope", path=""), path="scope")
    
    theory = _require_mapping(_require_field(report, "theory", path=""), path="theory")
    
    analysis = _require_mapping(_require_field(report, "analysis", path=""), path="analysis")
    
    clusters = _require_sequence(_require_field(report, "clusters", path=""), path="clusters")
    
    facts: list[dict[str, Any]] = []
    known_fact_ids: set[str] = set()
    
    _add_fact(
        facts,
        known_fact_ids,
        fact_id="purpose",
        source_path="purpose",
        value=_require_field(report, "purpose", path="")
    )
    
    _add_fields(
        facts,
        known_fact_ids,
        source=scope,
        fields=(
            "goal",
            "creates_new_norms",
            "refinement_role",
            "application_decision"
        ),
        fact_prefix="scope",
        source_prefix="scope"
    )
    
    _add_fields(
        facts,
        known_fact_ids,
        source=analysis,
        fields=(
            "model_count",
            "cluster_count",
            "reported_pattern_count",
            "refinement_candidate_count"
        ),
        fact_prefix="analysis",
        source_prefix="analysis"
    )
    
    for optional_theory_field in ("name", "source"):
        if optional_theory_field not in theory:
            continue
        
        _add_fact(
            facts,
            known_fact_ids,
            fact_id=f"theory.{optional_theory_field}",
            source_path=f"theory.{optional_theory_field}",
            value=theory[optional_theory_field]
        )
        
    for cluster_index, cluster_value in enumerate(clusters):
        cluster = _require_mapping(cluster_value, path=f"clusters[{cluster_index}]")
        
        _add_cluster_facts(facts, known_fact_ids, cluster=cluster, cluster_index=cluster_index)
        
    facts.sort(key=lambda fact: fact["id"])
    
    return {
        "schema_version": VERBALIZATION_FACTS_SCHEMA_VERSION,
        "source": {
            "report_schema_version": report_schema_version
        },
        "facts": facts
    }

def canonical_verbalization_facts_bytes(verbalization_facts: Mapping[str, Any]) -> bytes:
    """
    Serialize verbalization facts into canonical UTF-8 JSON bytes
    """
    if not isinstance(verbalization_facts, Mapping):
        raise TypeError("Verbalization facts must be a mapping.")
    
    canonical_json = json.dumps(
        verbalization_facts,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":")
    )
    
    return canonical_json.encode("utf-8")

def verbalization_facts_sha256(verbalization_facts: Mapping[str, Any]) -> str:
    """
    Return the SHA-256 hash of the canonical fact representation.
    """
    canonical_bytes = canonical_verbalization_facts_bytes(verbalization_facts)
    
    return hashlib.sha256(canonical_bytes).hexdigest()


def _require_field(mapping: Mapping[str, Any], field: str, *, path: str) -> Any:
    if field not in mapping:
        field_path = (f"{path}.{field}" if path else field)
        
        raise ValueError(f"Missing required report field: {field_path}")
    
    return mapping[field]

def _require_mapping(value: Any, *, path: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ValueError(f"Report field '{path}' must be a mapping.")
    
    return value

def _require_sequence(value: Any, *, path: str) -> Sequence[Any]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes, bytearray)):
        raise ValueError(f"Report field '{path}' must be a sequence.")
    
    return value

def _add_fact(facts: list[dict[str, Any]], known_fact_ids: set[str], *, fact_id: str, source_path: str, value: Any) -> None:
    if fact_id in known_fact_ids:
        raise ValueError(f"Duplicate fact id: {fact_id}")
    
    facts.append({
        "id": fact_id,
        "source_path": source_path,
        "value": deepcopy(value)
    })
    
    known_fact_ids.add(fact_id)
    
def _add_fields(facts: list[dict[str, Any]], known_fact_ids: set[str], *, source: Mapping[str, Any], fields: Sequence[str], fact_prefix: str, source_prefix: str) -> None:
    for field in fields:
        fact_id = (f"{fact_prefix}.{field}" if fact_prefix else field)
        source_path = (f"{source_prefix}.{field}" if source_prefix else field)
        value = _require_field(source, field, path=source_prefix)
        _add_fact(facts, known_fact_ids, fact_id = fact_id, source_path=source_path, value=value)
        
def _add_representative_model_facts(facts: list[dict[str,Any]], known_fact_ids: set[str], *, representative_model: Mapping[str, Any], cluster_id: int, source_path: str) -> None:
    fact_prefix = (f"cluster.{cluster_id}.representative_model")
    
    _add_fields(facts, known_fact_ids, source=representative_model, 
        fields=(
            "model_id",
            "graph_index",
            "logic",
            "kind",
            "cardinality",
            "relation",
            "designated_world",
            "atoms",
            "worlds",
            "edges"
        ), 
        fact_prefix=fact_prefix, 
        source_prefix=source_path
    )
    
    for optional_field in ("verification", "warnings"):
        if optional_field not in representative_model:
            continue
        
        _add_fact(
            facts,
            known_fact_ids,
            fact_id=(f"{fact_prefix}.{optional_field}"),
            source_path=(f"{source_path}.{optional_field}"),
            value=representative_model[optional_field]
        )

def _add_pattern_facts(facts: list[dict[str, Any]], known_fact_ids: set[str], *, pattern: Mapping[str, Any], cluster_id: int, source_path: str) -> None:
    pattern_id = _require_field(pattern, "pattern_id", path=source_path)
    
    if not isinstance(pattern_id, str) or not pattern_id:
        raise ValueError(f"Report field "
                         f"'{source_path}.pattern_id' "
                         "must be a non-empty string.")
        
    fact_prefix = f"cluster.{cluster_id}.pattern.{pattern_id}"
    
    _add_fields(
        facts, 
        known_fact_ids,
        source=pattern,
        fields=(
            "pattern_id",
            "pattern",
            "cluster_support",
            "outside_support",
            "contrast",
            "occurring_model_count",
            "representative_occurrence",
            "refinement_candidate"
        ),
        fact_prefix=fact_prefix,
        source_prefix=source_path
    )
    
def _add_cluster_facts(facts: list[dict[str, Any]], known_fact_ids: set[str], *, cluster: Mapping[str, Any], cluster_index: int) -> None:
    source_path = f"clusters[{cluster_index}]"
    
    cluster_id = _require_field(cluster, "cluster_id", path=source_path)
    
    if not isinstance(cluster_id, int) or isinstance(cluster_id, bool):
        raise ValueError(f"Report field "
                         f"'{source_path}.cluster_id' "
                         "must be an integer.")
    
    fact_prefix = f"cluster.{cluster_id}"
    _add_fields(facts, known_fact_ids, source=cluster, fields=(
        "cluster_id",
        "model_count",
        "model_fraction",
        "model_indices"
    ), fact_prefix=fact_prefix, source_prefix=source_path)
    
    representative_model = _require_mapping(
        _require_field(cluster, "representative_model", path=source_path),
        path=f"{source_path}.representative_model"
    )
    
    _add_representative_model_facts(facts, known_fact_ids, representative_model=representative_model, cluster_id=cluster_id, source_path=f"{source_path}.representative_model")
    
    patterns = _require_sequence(_require_field(cluster, "characteristic_patterns", path=source_path), path=f"{source_path}.characteristic_patterns")
    
    for pattern_index, pattern_value in enumerate(patterns):
        pattern_path = f"{source_path}.characteristic_patterns[{pattern_index}]"
        
        pattern = _require_mapping(pattern_value, path=pattern_path)
        
        _add_pattern_facts(
            facts,
            known_fact_ids,
            pattern=pattern,
            cluster_id=cluster_id,
            source_path=pattern_path
        )