import json

from graph_ml.io_schema import parse_model


def test_parse_model_preserves_report_relevant_model_metadata(
    tmp_path,
):
    model_file = tmp_path / "model.json"

    model_file.write_text(
        json.dumps(
            {
                "metadata": {
                    "iteration": 1,
                    "theory_name": "Example",
                },
                "model": {
                    "logic": "sdl",
                    "kind": "countermodel",
                    "cardinality": 2,
                    "relation": "R",
                    "designated_world": {
                        "index": 1,
                        "name": "i2",
                        "role": "initial_world",
                    },
                    "atoms": [
                        "go",
                        "tell",
                    ],
                    "edges": [
                        [0, 1],
                    ],
                    "valuations": {
                        "go": [
                            True,
                            False,
                        ],
                        "tell": [
                            False,
                            True,
                        ],
                    },
                    "warnings": [
                        "example warning",
                    ],
                },
            }
        ),
        encoding="utf-8",
    )

    metadata, graph = parse_model(model_file)

    assert metadata == {
        "iteration": 1,
        "theory_name": "Example",
    }

    assert graph.graph["atoms"] == (
        "go",
        "tell",
    )

    assert graph.graph["designated_world"] == {
        "index": 1,
        "name": "i2",
        "role": "initial_world",
    }

    assert graph.graph["warnings"] == [
        "example warning",
    ]

    assert graph.nodes[0]["designated"] is False
    assert graph.nodes[1]["designated"] is True