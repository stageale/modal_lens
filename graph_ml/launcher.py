from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from .clustering import hierarchical_cluster
from .features import feature_matrix, feature_vector
from .io_schema import parse_model
from .mining import cluster_patterns
from .report import write_report_json


RESULT_SCHEMA = "modal-lens/graph-analysis-result"
RESULT_SCHEMA_VERSION = "1.0"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the Axiom Refiner graph-analysis pipeline.")
    parser.add_argument("models", nargs="+", help="Exported model JSON files")
    parser.add_argument("--theory", required=True, help="Isabelle theory file")
    parser.add_argument("--output", required=True, help="Target report.json")
    parser.add_argument("--feature-method", default="combined", choices=("raw", "wl", "graphlet", "combined"))
    parser.add_argument("--graphlet-size", type=int, default=3)
    arguments = parser.parse_args(argv)

    try:
        response = launch_analysis(
            arguments.models,
            theory_path=arguments.theory,
            output_path=arguments.output,
            feature_method=arguments.feature_method,
            graphlet_size=arguments.graphlet_size
        )
    except Exception as error:
        print(
            json.dumps(
                {
                    "status": "failed",
                    "error_type": type(error).__name__,
                    "error": str(error)
                },
                ensure_ascii=False
            ),
            file=sys.stderr
        )
        return 1
    print(json.dumps(response, ensure_ascii=False, sort_keys=True))
    return 0

def launch_analysis(
    model_paths: Sequence[str | Path],
    *,
    theory_path: str | Path,
    output_path: str | Path,
    feature_method: str = "combined",
    graphlet_size: int = 3
) -> dict[str, Any]:
    if not model_paths:
        raise ValueError("At least one model JSON file is required.")
    if graphlet_size < 1:
        raise ValueError("Graphlet size must be positive.")
    
    graphs = []
    
    for graph_index, model_path in enumerate(model_paths):
        model_path = Path(model_path).resolve()
        metadata, graph = parse_model(model_path)
        
        iteration = metadata.get("iteration")
        
        graph.graph["model_id"] = str(metadata.get("run_id") or f"model-{int(iteration):03d}" if iteration is not None else model_path.parent.name)
        graph.graph["graph_index"] = graph_index
        graphs.append(graph)
        
    vectors = [feature_vector(graph, method=feature_method) for graph in graphs]
    matrix = feature_matrix(vectors)
    cluster_labels = hierarchical_cluster(matrix)
    pattern_results = cluster_patterns(graphs, cluster_labels, size=graphlet_size)
    highlights = _pattern_highlights(graphs, cluster_labels, pattern_results)
    theory = _theory_report(Path(theory_path).resolve())
    report_path = Path(output_path).resolve()
    
    report = write_report_json(
        report_path,
        theory=theory,
        graphs=graphs,
        cluster_labels=cluster_labels,
        cluster_pattern_results=pattern_results,
        highlights=highlights
    )
    
    return {
        "schema": RESULT_SCHEMA,
        "schema_version": RESULT_SCHEMA_VERSION,
        "status": "completed",
        "report_path": str(report_path),
        "model_count": report["analysis"]["model_count"],
        "cluster_count": report["analysis"]["cluster_count"],
        "feature_method": feature_method,
        "graphlet_size": graphlet_size
    }
    
def _pattern_highlights(
    graphs,
    cluster_labels,
    pattern_results,
):
    highlights = []

    for graph_index, graph in enumerate(graphs):
        cluster_label = int(cluster_labels[graph_index])
        patterns = pattern_results.get(cluster_label, ())
        highlight = None

        for pattern in patterns:
            occurrences = pattern.get(
                "occurrences",
                {},
            ).get(graph_index, ())

            if not occurrences:
                continue

            worlds = tuple(occurrences[0])
            world_set = set(worlds)

            highlight = {
                "basis": "pattern",
                "scope": "cluster",
                "world_scores": [
                    {
                        "world": world,
                        "score": 1.0,
                    }
                    for world in worlds
                ],
                "edge_scores": [
                    {
                        "source": source,
                        "target": target,
                        "score": 1.0,
                    }
                    for source, target in graph.edges
                    if source in world_set
                    and target in world_set
                ],
                "tags": [
                    "strongest_characteristic_pattern"
                ],
                "metadata": {
                    "cluster_id": cluster_label,
                    "contrast": float(
                        pattern["contrast"]
                    ),
                    "cluster_support": float(
                        pattern["cluster_support"]
                    ),
                },
            }

            break

        highlights.append(
            {
                "graph_index": graph_index,
                "model_id": graph.graph["model_id"],
                "cluster_id": cluster_label,
                "highlight": highlight,
            }
        )

    return highlights

def _theory_report(path: Path) -> dict[str, str]:
    return {
        "name": path.stem,
        "source": str(path),
        "content": path.read_text(encoding="utf-8")
    }
    
if __name__ == "__main__":
    raise SystemExit(main())