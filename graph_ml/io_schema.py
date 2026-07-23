from pathlib import Path
import json

import networkx as nx


def _read_model(file_path: Path) -> tuple[dict, dict]:
    with file_path.open("r", encoding="utf-8") as file:
        data = json.load(file)

    return data["metadata"], data["model"]


def _dict_to_nx_graph(model: dict) -> nx.DiGraph:
    graph = nx.DiGraph()

    graph.add_nodes_from(range(model["cardinality"]))

    for atom, values in model.get("valuations", {}).items():
        nx.set_node_attributes(graph, dict(enumerate(values)), atom)

    designated = model["designated_world"]

    if isinstance(designated, dict):
        designated = designated["index"]

    nx.set_node_attributes(graph, False, "designated")
    graph.nodes[designated]["designated"] = True

    relation = model.get("relation", "R")

    graph.add_edges_from((source, target, {"label": relation}) for source, target in model["edges"])

    graph.graph["logic"] = model.get("logic")
    graph.graph["kind"] = model.get("kind")
    graph.graph["relation"] = relation

    return graph


def parse_model(file_path: Path) -> tuple[dict, nx.DiGraph]:
    metadata, model = _read_model(file_path)
    graph = _dict_to_nx_graph(model)

    graph.graph["metadata"] = metadata
    graph.graph["source_file"] = file_path

    return metadata, graph