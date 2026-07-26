import networkx as nx
import pytest

import graph_ml.mining as mining


@pytest.fixture(autouse=True)
def deterministic_graphlet_stubs(monkeypatch):
    """
    Isoliert die Pattern-Mining-Logik von den konkreten Details der
    Graphlet-Kanonisierung in graph_ml.features.
    """

    monkeypatch.setattr(
        mining,
        "_model_atoms",
        lambda graph: {
            node: graph.nodes[node].get("atom")
            for node in graph.nodes
        },
    )

    # Für diese Tests reicht die Anzahl der Kanten als kanonische Darstellung:
    # Ein Pfad mit drei Knoten besitzt zwei Kanten,
    # ein gerichtetes Dreieck besitzt drei Kanten.
    monkeypatch.setattr(
        mining,
        "_canonical_graphlet",
        lambda graph, worlds, atoms:
            graph.subgraph(worlds).number_of_edges(),
    )


def directed_graph(nodes, edges):
    graph = nx.DiGraph()
    graph.add_nodes_from(nodes)
    graph.add_edges_from(edges)
    return graph


def path3():
    return directed_graph(
        [0, 1, 2],
        [
            (0, 1),
            (1, 2),
        ],
    )


def path4():
    return directed_graph(
        [0, 1, 2, 3],
        [
            (0, 1),
            (1, 2),
            (2, 3),
        ],
    )


def triangle3():
    return directed_graph(
        [0, 1, 2],
        [
            (0, 1),
            (1, 2),
            (2, 0),
        ],
    )


def test_pattern_occurrences_keeps_only_weakly_connected_induced_subgraphs():
    pattern = ("graphlet", 3, 2)

    assert mining.pattern_occurrences(path4()) == {
        pattern: [
            (0, 1, 2),
            (1, 2, 3),
        ]
    }


def test_pattern_occurrences_returns_empty_when_size_exceeds_node_count():
    assert mining.pattern_occurrences(path3(), size=4) == {}


def test_graph_patterns_returns_only_pattern_keys():
    assert mining.graph_patterns(path4()) == {
        ("graphlet", 3, 2)
    }


def test_frequent_patterns_counts_graph_support_not_number_of_occurrences():
    graphs = [
        path4(),
        path3(),
        triangle3(),
    ]

    result = mining.frequent_patterns(
        graphs,
        min_support=2 / 3,
    )

    # Das Pfadmuster kommt in path4() zweimal vor.
    # Trotzdem trägt der Graph nur einmal zum Support bei.
    assert result == {
        ("graphlet", 3, 2): pytest.approx(2 / 3)
    }


def test_frequent_patterns_returns_empty_for_empty_input():
    assert mining.frequent_patterns([]) == {}


def test_cluster_patterns_computes_support_contrast_and_occurrences():
    graphs = [
        path4(),
        path3(),
        triangle3(),
        triangle3(),
    ]

    labels = [0, 0, 1, 1]

    result = mining.cluster_patterns(
        graphs,
        labels,
        min_support=1.0,
        min_contrast=1.0,
    )

    assert set(result) == {0, 1}

    path_result = result[0][0]

    assert path_result["pattern"] == (
        "graphlet",
        3,
        2,
    )

    assert path_result["cluster_support"] == pytest.approx(1.0)
    assert path_result["outside_support"] == pytest.approx(0.0)
    assert path_result["contrast"] == pytest.approx(1.0)

    assert path_result["occurrences"] == {
        0: [
            (0, 1, 2),
            (1, 2, 3),
        ],
        1: [
            (0, 1, 2),
        ],
    }

    triangle_result = result[1][0]

    assert triangle_result["pattern"] == (
        "graphlet",
        3,
        3,
    )

    assert triangle_result["cluster_support"] == pytest.approx(1.0)
    assert triangle_result["outside_support"] == pytest.approx(0.0)
    assert triangle_result["contrast"] == pytest.approx(1.0)

    assert triangle_result["occurrences"] == {
        2: [
            (0, 1, 2),
        ],
        3: [
            (0, 1, 2),
        ],
    }


def test_cluster_patterns_uses_zero_outside_support_for_single_cluster():
    result = mining.cluster_patterns(
        [
            path3(),
            path3(),
        ],
        [7, 7],
        min_support=1.0,
        min_contrast=1.0,
    )

    assert result[7][0]["outside_support"] == pytest.approx(0.0)
    assert result[7][0]["contrast"] == pytest.approx(1.0)


def test_cluster_patterns_rejects_mismatched_lengths():
    with pytest.raises(
        ValueError,
        match="graphs and cluster labels must match",
    ):
        mining.cluster_patterns(
            [path3()],
            [],
        )


def test_pattern_support_is_fraction_of_containing_graphs():
    pattern = ("graphlet", 3, 2)

    result = mining.pattern_support(
        pattern,
        [
            path4(),
            path3(),
            triangle3(),
        ],
    )

    assert result == pytest.approx(2 / 3)
    assert mining.pattern_support(pattern, []) == 0.0


def test_current_implementation_requires_a_directed_graph():
    graph = nx.Graph(
        [
            (0, 1),
            (1, 2),
        ]
    )

    with pytest.raises(nx.NetworkXNotImplemented):
        mining.pattern_occurrences(graph)
        
def test_cluster_patterns_uses_pattern_as_canonical_tie_breaker(
    monkeypatch,
):
    first_pattern = (
        "graphlet",
        3,
        "z-pattern",
    )

    second_pattern = (
        "graphlet",
        3,
        "a-pattern",
    )

    monkeypatch.setattr(
        mining,
        "pattern_occurrences",
        lambda graph, size: {
            first_pattern: [
                (0, 1, 2),
            ],
            second_pattern: [
                (0, 1, 2),
            ],
        },
    )

    result = mining.cluster_patterns(
        [
            path3(),
            path3(),
        ],
        [
            0,
            0,
        ],
        min_support=1.0,
        min_contrast=1.0,
    )

    assert [
        item["pattern"]
        for item in result[0]
    ] == [
        second_pattern,
        first_pattern,
    ]