import networkx as nx
from graph_ml.report import build_report

def test_build_report_uses_declared_atoms_and_designated_world_index():
    graph = nx.DiGraph()

    graph.add_node(
        0,
        go=True,
        tell=False,
        designated=False,
    )

    graph.add_node(
        1,
        go=False,
        tell=True,
        designated=True,
    )

    graph.add_edge(
        0,
        1,
        label="R",
    )

    graph.graph.update(
        {
            "logic": "sdl",
            "kind": "countermodel",
            "relation": "R",
            "atoms": (
                "go",
                "tell",
            ),
            "designated_world": {
                "index": 1,
                "name": "i2",
                "role": "initial_world",
            },
            "warnings": [
                "example warning",
            ],
        }
    )

    report = build_report(
        theory=(
            "theory Example "
            "imports Main "
            "begin end"
        ),
        graphs=[graph],
        cluster_labels=[0],
        cluster_pattern_results={
            0: [],
        },
    )

    representative = report[
        "clusters"
    ][0]["representative_model"]

    assert representative["atoms"] == [
        "go",
        "tell",
    ]

    assert representative[
        "designated_world"
    ] == 1

    assert representative["warnings"] == [
        "example warning",
    ]
    
def test_build_report_does_not_infer_designated_as_an_atom():
    graph = nx.DiGraph()

    graph.add_node(
        0,
        p=True,
        designated=True,
    )

    graph.graph["designated_world"] = 0

    report = build_report(
        theory=(
            "theory Example "
            "imports Main "
            "begin end"
        ),
        graphs=[graph],
        cluster_labels=[0],
        cluster_pattern_results={
            0: [],
        },
    )

    representative = report[
        "clusters"
    ][0]["representative_model"]

    assert representative["atoms"] == [
        "p",
    ]