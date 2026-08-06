import json 
import os 
import tempfile 
import networkx as nx

from collections.abc import Mapping
from pathlib import Path
from typing import Any


MODEL_SCHEMA = "modallens/model"
MODEL_SCHEMA_VERSION = "1.0"


def _read_model(file_path: Path) -> tuple[dict, dict]:
    with file_path.open("r", encoding="utf-8") as file:
        document = json.load(file)

    if not isinstance(document, Mapping):
        raise ValueError(
            f"Model document must be a JSON object: {file_path}"
        )

    if document.get("schema") != MODEL_SCHEMA:
        raise ValueError(
            f"Unsupported model schema in {file_path}: "
            f"{document.get('schema')!r}"
        )

    if document.get("schema_version") != MODEL_SCHEMA_VERSION:
        raise ValueError(
            f"Unsupported model schema version in {file_path}: "
            f"{document.get('schema_version')!r}"
        )

    metadata = document.get("metadata")
    model = document.get("model")

    if not isinstance(metadata, dict):
        raise ValueError(
            f"Model metadata must be a JSON object: {file_path}"
        )

    if not isinstance(model, dict):
        raise ValueError(
            f"Model data must be a JSON object: {file_path}"
        )

    return metadata, model


def _dict_to_nx_graph(model: Mapping[str, Any]) -> nx.DiGraph:
    graph = nx.DiGraph()

    graph.add_nodes_from(range(model["cardinality"]))

    for atom, values in model.get("valuations", {}).items():
        nx.set_node_attributes(graph, dict(enumerate(values)), atom)

    designated_world = model["designated_world"]

    if isinstance(designated_world, dict):
        designated_index = designated_world["index"]
    else:
        designated_index = designated_world

    nx.set_node_attributes(graph, False, "designated")
    graph.nodes[designated_index]["designated"] = True

    relation = model.get("relation", "R")

    graph.add_edges_from((source, target, {"label": relation}) for source, target in model["edges"])

    graph.graph["logic"] = model.get("logic")
    graph.graph["kind"] = model.get("kind")
    graph.graph["relation"] = relation
    
    graph.graph["atoms"] = tuple(str(atom) for atom in model.get("atoms", model.get("valuations", {})))
    graph.graph["designated_world"] = (dict(designated_world) if isinstance(designated_world, Mapping) else designated_world)
    graph.graph["warnings"] = list(model.get("warnings", []))

    return graph


def parse_model(file_path: Path) -> tuple[dict, nx.DiGraph]:
    metadata, model = _read_model(file_path)
    graph = _dict_to_nx_graph(model)

    graph.graph["metadata"] = metadata
    graph.graph["source_file"] = file_path

    return metadata, graph

def write_report_json(report: Mapping[str, Any], output_path : str | Path) -> Path:
    if not isinstance(report, Mapping):
        raise TypeError("Report must be a mapping.")
    
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
            
            json.dump(
                report, 
                temporary_file,
                ensure_ascii=False,
                indent=2,
                allow_nan=False
            )
            
            temporary_file.write("\n")
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_path, path)
        
    except Exception:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
            
        raise
    
    
    return path