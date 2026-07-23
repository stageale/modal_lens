import numpy as np
import pytest
from scipy.sparse import csr_matrix
import networkx as nx

from graph_ml.clustering import (
    cluster_models,
    hierarchical_cluster,
    similarity_matrix,
)

from graph_ml.features import (
    feature_matrix,
    graphlet_feature_vector,
    wl_feature_vector
)


def test_similarity_matrix_uses_cosine_similarity():
    features = csr_matrix([
        [1, 0],
        [1, 0],
        [0, 1],
    ])

    similarities = similarity_matrix(features)

    assert np.allclose(
        similarities,
        [
            [1, 1, 0],
            [1, 1, 0],
            [0, 0, 1],
        ],
    )


def test_hierarchical_cluster_groups_similar_models():
    features = csr_matrix([
        [1.0, 0.0],
        [0.9, 0.1],
        [0.0, 1.0],
        [0.1, 0.9],
    ])

    labels = hierarchical_cluster(
        features,
        n_clusters=2,
    )

    assert labels[0] == labels[1]
    assert labels[2] == labels[3]
    assert labels[0] != labels[2]


def test_hierarchical_cluster_handles_empty_input():
    features = csr_matrix((0, 2))

    labels = hierarchical_cluster(features)

    assert labels.size == 0


def test_hierarchical_cluster_handles_single_model():
    features = csr_matrix([
        [1.0, 0.0],
    ])

    labels = hierarchical_cluster(features)

    assert labels.tolist() == [0]


def test_hierarchical_cluster_selects_two_clear_clusters():
    features = csr_matrix([
        [1.0, 0.0],
        [0.95, 0.05],
        [0.0, 1.0],
        [0.05, 0.95],
    ])

    labels = hierarchical_cluster(features)

    assert len(set(labels)) == 2
    assert labels[0] == labels[1]
    assert labels[2] == labels[3]
    assert labels[0] != labels[2]


def test_cluster_models_returns_cluster_medoid():
    graphs = [
        "left",
        "middle",
        "right",
    ]

    features = csr_matrix([
        [1.0, 0.0],
        [1.0, 1.0],
        [0.0, 1.0],
    ])

    clusters = cluster_models(
        graphs,
        features,
        n_clusters=1,
    )

    assert len(clusters) == 1

    cluster = clusters[0]

    assert cluster["indices"] == [0, 1, 2]
    assert cluster["models"] == graphs
    assert cluster["medoid_index"] == 1
    assert cluster["medoid"] == "middle"


def test_cluster_models_returns_one_medoid_per_cluster():
    graphs = [
        "a",
        "b",
        "c",
        "d",
    ]

    features = csr_matrix([
        [1.0, 0.0],
        [0.9, 0.1],
        [0.0, 1.0],
        [0.1, 0.9],
    ])

    clusters = cluster_models(
        graphs,
        features,
        n_clusters=2,
    )

    assert len(clusters) == 2

    clustered_indices = sorted(
        index
        for cluster in clusters
        for index in cluster["indices"]
    )

    assert clustered_indices == [0, 1, 2, 3]

    for cluster in clusters:
        assert cluster["medoid_index"] in cluster["indices"]
        assert cluster["medoid"] in cluster["models"]


def test_cluster_models_rejects_mismatched_input_sizes():
    features = csr_matrix([
        [1.0, 0.0],
        [0.0, 1.0],
    ])

    with pytest.raises(
        ValueError,
        match="must match",
    ):
        cluster_models(
            ["only one graph"],
            features,
        )
        
        
def test_clustering_separates_propositional_kripke_patterns():
    first = nx.DiGraph()
    first.graph["atoms"] = ("p", "q")
    first.add_node(0, p=True, q=False)
    first.add_node(1, p=False, q=True)
    first.add_edge(0, 1, label="R")

    renamed_first = nx.DiGraph()
    renamed_first.graph["atoms"] = ("p", "q")
    renamed_first.add_node("a", p=True, q=False)
    renamed_first.add_node("b", p=False, q=True)
    renamed_first.add_edge("a", "b", label="R")

    second = nx.DiGraph()
    second.graph["atoms"] = ("p", "q")
    second.add_node(0, p=True, q=False)
    second.add_node(1, p=True, q=True)
    second.add_edge(0, 1, label="R")

    renamed_second = nx.DiGraph()
    renamed_second.graph["atoms"] = ("p", "q")
    renamed_second.add_node("x", p=True, q=False)
    renamed_second.add_node("y", p=True, q=True)
    renamed_second.add_edge("x", "y", label="R")

    graphs = [
        first,
        renamed_first,
        second,
        renamed_second,
    ]

    feature_vectors = [
        {
            **wl_feature_vector(graph),
            **graphlet_feature_vector(graph, size=2),
        } for graph in graphs
    ]

    features = feature_matrix(feature_vectors)

    labels = hierarchical_cluster(
        features,
        n_clusters=2,
    )

    assert labels[0] == labels[1]
    assert labels[2] == labels[3]
    assert labels[0] != labels[2]