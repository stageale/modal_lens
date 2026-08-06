from __future__ import annotations

import json
from pathlib import Path

import pytest

from graph_ml.io_schema import parse_model, write_report_json


def _model_document() -> dict:
    return {
        "schema": "modal-lens/model",
        "schema_version": "1.0",
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
            "atoms": ["go", "tell"],
            "edges": [[0, 1]],
            "valuations": {
                "go": [True, False],
                "tell": [False, True],
            },
            "warnings": ["example warning"],
        },
    }


def test_parse_model_preserves_report_relevant_metadata(tmp_path: Path) -> None:
    model_file = tmp_path / "model.json"
    model_file.write_text(json.dumps(_model_document()), encoding="utf-8")

    metadata, graph = parse_model(model_file)

    assert metadata == {"iteration": 1, "theory_name": "Example"}
    assert graph.graph["atoms"] == ("go", "tell")
    assert graph.graph["designated_world"] == {
        "index": 1,
        "name": "i2",
        "role": "initial_world",
    }
    assert graph.graph["warnings"] == ["example warning"]
    assert graph.nodes[0]["designated"] is False
    assert graph.nodes[1]["designated"] is True
    assert graph.edges[0, 1]["label"] == "R"


@pytest.mark.parametrize(
    ("field", "value", "message"),
    [
        ("schema", "other/model", "Unsupported model schema"),
        ("schema_version", "2.0", "Unsupported model schema version"),
        ("metadata", [], "metadata must be a JSON object"),
        ("model", [], "data must be a JSON object"),
    ],
)
def test_parse_model_rejects_invalid_envelopes(
    tmp_path: Path,
    field: str,
    value: object,
    message: str,
) -> None:
    document = _model_document()
    document[field] = value
    model_file = tmp_path / f"invalid-{field}.json"
    model_file.write_text(json.dumps(document), encoding="utf-8")

    with pytest.raises(ValueError, match=message):
        parse_model(model_file)


def test_write_report_json_is_atomic_and_requires_json_suffix(tmp_path: Path) -> None:
    report = {"schema": "example", "values": [1, 2, 3]}
    output = tmp_path / "nested" / "report.json"

    assert write_report_json(report, output) == output
    assert json.loads(output.read_text(encoding="utf-8")) == report
    assert not list(output.parent.glob("*.tmp"))

    with pytest.raises(ValueError, match=".json suffix"):
        write_report_json(report, tmp_path / "report.txt")

    with pytest.raises(TypeError, match="mapping"):
        write_report_json([], output)
