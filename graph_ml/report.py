from __future__ import annotations

import json
import os
import tempfile
from collections import defaultdict
from collections.abc import Iterable, Mapping, Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import networkx as nx 

def _json_value(value: Any) -> Any:
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    elif isinstance(value, Path):
        return str(value)
    elif isinstance(value, Mapping):
        return {str(key): _json_value(item) for key, item in value.items()}
    elif isinstance(value, (list, tuple, set, frozenset)):
        return [_json_value(item) for item in value]
    
    item = getattr(value, "item", None)
    
    if callable(item):
        return _json_value(item())
    
    raise TypeError(f"Value of type {type(value).__name__} is not JSON serializable: {value!r}")

def _normalize_theory(theory: Mapping[str, Any] | str | Path) -> dict[str, Any]:
    if isinstance(theory, Mapping):
        return _json_value(dict(theory))
    if isinstance(theory, Path):
        return {
            "source": str(theory),
            "content": theory.read_text(encoding="utf-8")
        }
    if isinstance(theory, str):
        return {"content": theory}
    
    raise TypeError("Theory must be a mapping, a string, or a Path.")

def _graph_atoms(graph: nx.DiGraph) -> list[str]:
    declared_atoms = graph.graph.get("atoms")
    
    if declared_atoms is not None:
        return [str(atom) for atom in declared_atoms]
    
    ignored_attributes = {"name", "label", "role", "index"}
    
    atoms: set[str] = set()
    
    for _, attributes in graph.nodes(data=True):
        atoms.update(str(key) for key, value in attributes.items() if key not in ignored_attributes and isinstance(value, bool))
        
    return sorted(atoms)

def _designated_world(graph: nx.DiGraph) -> Any:
    designated_world = graph.graph.get("designated_world")
    
    if isinstance(designated_world, Mapping):
        return designated_world.get("index", _designated_world.get("name", designated_world))
    return designated_world

def _model_id(graph: nx.DiGraph, graph_index: int) -> str:
    return str(graph.graph.get("model_id") or graph.graph.get("id") or graph.graph.get("source") or f"model-{graph_index}")

def _model_report(graph: nx.DiGraph, graph_index: int) -> dict[str, Any]:
    atoms = _graph_atoms(graph)
    relation = str(graph.graph.get("relation", "R"))
    
    worlds = []
    
    for world, attributes in graph.nodes(data=True):
        worlds.append({
            "id": _json_value(world),
            "valuations": {atom: bool(attributes.get(atom, False)) for atom in atoms}
        })
    
    edges = []
    
    for source, target, attributes in graph.edges(data=True):
        edge = {
            "source": _json_value(source),
            "target": _json_value(target)
        }
        
        label = attributes.get("label")
        
        if label is not None and str(label) != relation:
            edge["label"] = str(label)
            
        edges.append(edge)
        
    model = {
        "model_id": _model_id(graph, graph_index),
        "graph_index": graph_index,
        "logic": graph.graph.get("logic"),
        "kind": graph.graph.get("kind", "countermodel"),
        "cardinality": graph.number_of_nodes(),
        "relation": relation,
        "designated_world": _json_value(_designated_world(graph)),
        "atoms": atoms,
        "worlds": worlds,
        "edges": edges
    }
    
    if "verification" in graph.graph:
        model["verification"] = _json_value(graph.graph["verification"])
        
    if graph.graph.get("warnings"):
        model["warnings"] = _json_value(graph.graph["warnings"])
        
    return model


def _pattern_report(pattern_data: Mapping[str, Any], *, cluster_label: int, rank: int, graphs: Sequence[nx.DiGraph]) -> dict[str, Any]:
    occurrences = pattern_data.get("occurrences", {})

    occurrence_models = sorted(int(graph_index) for graph_index in occurrences)

    representative_occurrence = None

    if occurrence_models:
        graph_index = occurrence_models[0]
        first_occurrence = occurrences[graph_index][0]

        representative_occurrence = {
            "model_id": _model_id(
                graphs[graph_index],
                graph_index,
            ),
            "graph_index": graph_index,
            "worlds": _json_value(
                first_occurrence
            ),
        }

    return {
        "pattern_id": (
            f"cluster-{cluster_label}-pattern-{rank}"
        ),
        "pattern": _json_value(
            pattern_data["pattern"]
        ),
        "cluster_support": float(
            pattern_data["cluster_support"]
        ),
        "outside_support": float(
            pattern_data["outside_support"]
        ),
        "contrast": float(
            pattern_data["contrast"]
        ),
        "occurring_model_count": len(
            occurrence_models
        ),
        "representative_occurrence": (
            representative_occurrence
        ),
    }
    
    
def build_report(*, 
                 theory: Mapping[str, Any] | str | Path, 
                 graphs: Iterable[nx.DiGraph], 
                 cluster_labels: Iterable[int], 
                 cluster_pattern_results: Mapping[int, Sequence[Mapping[str, Any]],], 
                 max_patterns_per_cluster: int = 5) -> dict[str, Any]:
    """
    Build a report from a theory, clustered countermodels and mined patterns.

    The report describes structural indicators of possible normative gaps.
    It does not claim to derive or create new norms.
    """
    graphs = list(graphs)

    cluster_labels = [int(label) for label in cluster_labels]

    if len(graphs) != len(cluster_labels):
        raise ValueError("Number of graphs and cluster labels must match.")

    if max_patterns_per_cluster < 0:
        raise ValueError("max_patterns_per_cluster must be non-negative.")

    cluster_indices: dict[int, list[int]] = defaultdict(list)

    for graph_index, cluster_label in enumerate(cluster_labels):
        cluster_indices[cluster_label].append(graph_index)

    cluster_reports = []

    for cluster_label in sorted(cluster_indices):
        indices = cluster_indices[cluster_label]

        raw_patterns = list(cluster_pattern_results.get(cluster_label, ()))

        selected_patterns = raw_patterns[:max_patterns_per_cluster]

        patterns = [_pattern_report(pattern_data, cluster_label=cluster_label, rank=rank, graphs=graphs) for rank, pattern_data in enumerate(selected_patterns, start=1)]

        # Vorerst nehmen wir das erste Modell des Clusters.
        representative_index = indices[0]

        # Falls das stärkste Pattern in einem Modell vorkommt,
        # nehmen wir dieses Modell als Repräsentanten.
        if patterns:
            occurrence = patterns[0]["representative_occurrence"]

            if occurrence is not None:
                representative_index = occurrence["graph_index"]

        cluster_reports.append({
            "cluster_id": cluster_label,
            "model_count": len(indices),
            "model_fraction": (
                len(indices) / len(graphs)
                if graphs
                else 0.0
            ),
            "model_indices": indices,
            "characteristic_patterns": patterns,
            "representative_model": _model_report(
                graphs[representative_index],
                representative_index
            )
        })

    reported_pattern_count = sum(
        len(cluster["characteristic_patterns"])
        for cluster in cluster_reports
    )

    return {
        "schema_version": "1.0",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "purpose": "normative_gap_analysis",

        "scope": {
            "goal": (
                "Identify recurring structural indicators "
                "of possible normative gaps."
            ),
            "creates_new_norms": False,
            "refinement_role": (
                "diagnostic_support_for_human_deliberation"
            )
        },

        "theory": _normalize_theory(theory),

        "analysis": {
            "model_count": len(graphs),
            "cluster_count": len(cluster_indices),
            "reported_pattern_count": (reported_pattern_count),
        },

        "clusters": cluster_reports
    }
    
    
def write_report_json(
    output_path: str | Path,
    *,
    theory: Mapping[str, Any] | str | Path,
    graphs: Iterable[nx.DiGraph],
    cluster_labels: Iterable[int],
    cluster_pattern_results: Mapping[
        int,
        Sequence[Mapping[str, Any]],
    ],
    max_patterns_per_cluster: int = 5,
) -> dict[str, Any]:
    """
    Build and write a normative-gap analysis report.

    Returns the generated report dictionary.
    """
    report = build_report(
        theory=theory,
        graphs=graphs,
        cluster_labels=cluster_labels,
        cluster_pattern_results=(cluster_pattern_results),
        max_patterns_per_cluster=(max_patterns_per_cluster)
    )

    path = Path(output_path)

    if path.suffix.lower() != ".json":
        raise ValueError("Report output path must have a .json suffix.")

    path.parent.mkdir(parents=True, exist_ok=True)

    temporary_path: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False
        ) as temporary_file:
            temporary_path = Path(temporary_file.name)

            json.dump(report, temporary_file, ensure_ascii=False, indent=2, allow_nan=False)

            temporary_file.write("\n")
            temporary_file.flush()
            os.fsync(temporary_file.fileno())

        os.replace(temporary_path, path)

    except Exception:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)

        raise

    return report