import networkx as nx
import pytest
from scipy.sparse import csr_matrix

from graph_ml.features import (
    feature_matrix,
    feature_vector,
    graphlet_feature_vector,
    graphlet_features,
    raw_feature_vector,
    raw_features,
    wl_feature_vector,
    wl_features,
)
from graph_ml.mining import pattern_occurrences


@pytest.fixture
def model_graph():
    graph = nx.DiGraph()

    graph.graph["relation"] = "R"
    graph.graph["atoms"] = ("p", "q")

    graph.add_node(
        0,
        designated=True,
        p=True,
        q=False,
    )
    graph.add_node(
        1,
        designated=False,
        p=False,
        q=True,
    )
    graph.add_node(
        2,
        designated=False,
        p=True,
        q=True,
    )

    graph.add_edges_from([
        (0, 1, {"label": "R"}),
        (1, 2, {"label": "R"}),
    ])

    return graph


# ==================== Raw Features ====================


def test_raw_feature_vector(model_graph):
    assert raw_feature_vector(
        model_graph,
        modal_depth=2,
    ) == {
        "worlds": 3,
        "relations": 2,
        "density": pytest.approx(1 / 3),
        "designated_successors": 1,
        "reachable_worlds": 2,
        "k_step_reachable": 2,
    }


def test_raw_features_process_multiple_graphs(model_graph):
    assert raw_features(
        [model_graph],
        modal_depth=2,
    ) == [
        raw_feature_vector(
            model_graph,
            modal_depth=2,
        )
    ]


def test_raw_features_use_designated_world(model_graph):
    changed = model_graph.copy()

    changed.nodes[0]["designated"] = False
    changed.nodes[1]["designated"] = True

    original_features = raw_feature_vector(
        model_graph,
        modal_depth=2,
    )
    changed_features = raw_feature_vector(
        changed,
        modal_depth=2,
    )

    assert original_features != changed_features
    assert original_features["reachable_worlds"] == 2
    assert changed_features["reachable_worlds"] == 1


# ===================== WL Features =====================


def test_wl_counts_every_world(model_graph):
    features = wl_feature_vector(
        model_graph,
        iterations=0,
    )

    assert sum(features.values()) == 3


def test_wl_treats_designated_world_like_other_worlds(
    model_graph,
):
    changed = model_graph.copy()

    changed.nodes[0]["designated"] = False
    changed.nodes[1]["designated"] = True

    assert (
        wl_feature_vector(model_graph)
        == wl_feature_vector(changed)
    )


def test_wl_distinguishes_exact_world_valuations(
    model_graph,
):
    changed = model_graph.copy()

    changed.nodes[1]["p"] = True

    assert (
        wl_feature_vector(model_graph)
        != wl_feature_vector(changed)
    )


def test_wl_treats_missing_atom_as_false():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(
        0,
        p=True,
        q=False,
    )

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(
        0,
        p=True,
    )

    assert (
        wl_feature_vector(first, iterations=0)
        == wl_feature_vector(second, iterations=0)
    )


def test_wl_distinguishes_additional_true_atom():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(
        0,
        p=True,
        q=False,
    )

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(
        0,
        p=True,
        q=True,
    )

    assert (
        wl_feature_vector(first, iterations=0)
        != wl_feature_vector(second, iterations=0)
    )


def test_wl_valuation_ignores_attribute_order():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(
        0,
        designated=False,
        p=True,
        q=True,
    )

    second = nx.DiGraph()
    second.graph["atoms"] = ("q", "p")
    second.add_node(
        0,
        q=True,
        p=True,
        designated=True,
    )

    assert (
        wl_feature_vector(first, iterations=0)
        == wl_feature_vector(second, iterations=0)
    )


def test_wl_distinguishes_relation_direction():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(0, p=True, q=False)
    first.add_node(1, p=False, q=True)
    first.add_edge(0, 1, label="R")

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(0, p=True, q=False)
    second.add_node(1, p=False, q=True)
    second.add_edge(1, 0, label="R")

    assert (
        wl_feature_vector(first, iterations=1)
        != wl_feature_vector(second, iterations=1)
    )


def test_wl_distinguishes_relation_labels():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(0, p=True, q=False)
    first.add_node(1, p=False, q=True)
    first.add_edge(0, 1, label="R")

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(0, p=True, q=False)
    second.add_node(1, p=False, q=True)
    second.add_edge(0, 1, label="S")

    assert (
        wl_feature_vector(first, iterations=1)
        != wl_feature_vector(second, iterations=1)
    )


def test_wl_preserves_multiple_equal_successors():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(0, p=True, q=False)
    first.add_node(1, p=False, q=True)
    first.add_edge(0, 1, label="R")

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(0, p=True, q=False)
    second.add_node(1, p=False, q=True)
    second.add_node(2, p=False, q=True)

    second.add_edges_from([
        (0, 1, {"label": "R"}),
        (0, 2, {"label": "R"}),
    ])

    assert (
        wl_feature_vector(first, iterations=1)
        != wl_feature_vector(second, iterations=1)
    )


def test_wl_matches_renamed_kripke_structure():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(0, p=True, q=False)
    first.add_node(1, p=False, q=True)
    first.add_edge(0, 1, label="R")

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(
        "world_a",
        p=True,
        q=False,
    )
    second.add_node(
        "world_b",
        p=False,
        q=True,
    )
    second.add_edge(
        "world_a",
        "world_b",
        label="R",
    )

    assert (
        wl_feature_vector(first)
        == wl_feature_vector(second)
    )


def test_wl_features_process_multiple_graphs(
    model_graph,
):
    assert wl_features([model_graph]) == [
        wl_feature_vector(model_graph)
    ]


# ============== Kripke substructures ===============


def test_graphlet_counts_connected_kripke_structure(
    model_graph,
):
    features = graphlet_feature_vector(
        model_graph,
        size=3,
    )

    assert sum(features.values()) == 3
    assert {feature[1] for feature in features} == {2, 3}


def test_graphlet_ignores_disconnected_node_sets():
    graph = nx.DiGraph()
    graph.graph["atoms"] = ("p", "q")

    graph.add_node(0, p=True, q=False)
    graph.add_node(1, p=False, q=True)
    graph.add_node(2, p=True, q=True)

    graph.add_edge(0, 1, label="R")

    features = graphlet_feature_vector(
        graph,
        size=3,
    )

    assert sum(features.values()) == 1
    assert {feature[1] for feature in features} == {2}


def test_graphlet_treats_designated_world_like_other_worlds(
    model_graph,
):
    changed = model_graph.copy()

    changed.nodes[0]["designated"] = False
    changed.nodes[1]["designated"] = True

    assert (
        graphlet_feature_vector(model_graph)
        == graphlet_feature_vector(changed)
    )


def test_graphlet_distinguishes_exact_world_valuations(
    model_graph,
):
    changed = model_graph.copy()

    changed.nodes[1]["p"] = True

    assert (
        graphlet_feature_vector(model_graph)
        != graphlet_feature_vector(changed)
    )


def test_graphlet_treats_missing_atom_as_false():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(0, p=True)
    first.add_node(1, q=True)
    first.add_edge(0, 1, label="R")

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(0, p=True, q=False)
    second.add_node(1, p=False, q=True)
    second.add_edge(0, 1, label="R")

    assert (
        graphlet_feature_vector(first, size=2)
        == graphlet_feature_vector(second, size=2)
    )


def test_graphlet_distinguishes_additional_true_atom():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(0, p=True, q=False)
    first.add_node(1, p=False, q=True)
    first.add_edge(0, 1, label="R")

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(0, p=True, q=False)
    second.add_node(1, p=True, q=True)
    second.add_edge(0, 1, label="R")

    assert (
        graphlet_feature_vector(first, size=2)
        != graphlet_feature_vector(second, size=2)
    )


def test_graphlet_distinguishes_relation_direction():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(0, p=True, q=False)
    first.add_node(1, p=False, q=True)
    first.add_edge(0, 1, label="R")

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(0, p=True, q=False)
    second.add_node(1, p=False, q=True)
    second.add_edge(1, 0, label="R")

    assert (
        graphlet_feature_vector(first, size=2)
        != graphlet_feature_vector(second, size=2)
    )


def test_graphlet_distinguishes_relation_labels():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(0, p=True, q=False)
    first.add_node(1, p=False, q=True)
    first.add_edge(0, 1, label="R")

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(0, p=True, q=False)
    second.add_node(1, p=False, q=True)
    second.add_edge(0, 1, label="S")

    assert (
        graphlet_feature_vector(first, size=2)
        != graphlet_feature_vector(second, size=2)
    )


def test_graphlet_preserves_multimodal_edge_labels():
    graph = nx.DiGraph()
    graph.graph["atoms"] = ("p",)
    graph.add_node(0, p=True)
    graph.add_node(1, p=False)
    graph.add_edge(
        0,
        1,
        label=("settledness", "belief:provider"),
    )

    features = graphlet_feature_vector(graph, size=2)
    [(pattern, count)] = features.items()

    assert count == 1
    assert pattern[1] == 2
    assert (
        "belief:provider",
        "settledness",
    ) in {cell[1] for cell in pattern[2][1] if cell[0] == 1}


def test_graphlet_matches_renamed_kripke_structure():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(0, p=True, q=False)
    first.add_node(1, p=False, q=True)
    first.add_edge(0, 1, label="R")

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(
        "world_a",
        p=True,
        q=False,
    )
    second.add_node(
        "world_b",
        p=False,
        q=True,
    )
    second.add_edge(
        "world_a",
        "world_b",
        label="R",
    )

    assert (
        graphlet_feature_vector(first, size=2)
        == graphlet_feature_vector(second, size=2)
    )


def test_graphlet_features_process_multiple_graphs(
    model_graph,
):
    assert graphlet_features(
        [model_graph],
        size=3,
    ) == [
        graphlet_feature_vector(
            model_graph,
            size=3,
        )
    ]
    
def test_graphlet_feature_vector_accepts_occurrences(model_graph):
    occurrences = pattern_occurrences(model_graph, size=3)
    result = graphlet_feature_vector(model_graph, size=3, occurrences=occurrences)
    expected = graphlet_feature_vector(model_graph, size=3)
    
    assert result == expected


# ================= Combined Features =================


def test_combined_feature_vector_contains_all_features(model_graph):
    combined = feature_vector(model_graph, method="combined")

    raw = raw_feature_vector(model_graph)
    wl = wl_feature_vector(model_graph)
    graphlets = graphlet_feature_vector(model_graph)

    for feature, value in raw.items():
        assert combined[feature] == value

    for feature, value in wl.items():
        assert combined[feature] == value

    for feature, value in graphlets.items():
        assert combined[feature] == value


def test_feature_vector_rejects_unknown_method(model_graph):
    with pytest.raises(ValueError, match="Unknown feature method"):
        feature_vector(model_graph, method="unknown")
    
def test_feature_vector_respects_graphlet_size(model_graph):
    assert feature_vector(model_graph, method="graphlet", graphlet_size=2) == graphlet_feature_vector(model_graph, size=2)

# =================== Feature Matrix ===================


def test_feature_matrix_accepts_generator(model_graph):
    changed = model_graph.copy()
    changed.nodes[1]["p"] = True

    vectors = (
        wl_feature_vector(graph)
        for graph in [model_graph, changed]
    )

    matrix = feature_matrix(vectors)

    assert isinstance(matrix, csr_matrix)
    assert matrix.shape[0] == 2


def test_feature_matrix_aligns_identical_models(
    model_graph,
):
    matrix = feature_matrix([
        wl_feature_vector(model_graph),
        wl_feature_vector(model_graph.copy()),
    ])

    assert (
        matrix.getrow(0)
        != matrix.getrow(1)
    ).nnz == 0


def test_feature_matrix_separates_different_valuations(
    model_graph,
):
    changed = model_graph.copy()
    changed.nodes[1]["p"] = True

    matrix = feature_matrix([
        wl_feature_vector(model_graph),
        wl_feature_vector(changed),
    ])

    assert (
        matrix.getrow(0)
        != matrix.getrow(1)
    ).nnz > 0