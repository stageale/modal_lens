import networkx as nx
import pytest

from graph_ml.features import graphlet_features, raw_features, wl_features


@pytest.fixture
def model_graph():
    graph = nx.DiGraph()

    graph.add_nodes_from([0, 1, 2])

    nx.set_node_attributes(graph, False, "designated")
    graph.nodes[0]["designated"] = True

    nx.set_node_attributes(graph, False, "p")
    graph.nodes[0]["p"] = True

    graph.add_edges_from([
        (0, 1, {"label": "R"}),
        (1, 2, {"label": "R"}),
    ])

    return graph


def test_raw_features(model_graph):
    features = raw_features([model_graph], modal_depth=2)

    assert features == [{
        "worlds": 3,
        "designated_successors": 1,
        "reachable_worlds": 2,
        "k_step_reachable": 2,
    }]


def test_wl_features_include_valuations(model_graph):
    changed = model_graph.copy()
    changed.nodes[0]["p"] = False

    assert wl_features([model_graph])[0] != wl_features([changed])[0]


def test_graphlet_features_count_connected_graphlet(model_graph):
    features = graphlet_features([model_graph], size=3)[0]

    assert sum(features.values()) == 1