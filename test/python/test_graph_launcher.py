import json
from pathlib import Path

from graph_ml.launcher import launch_analysis


def test_launch_analysis_writes_report_and_highlight(
    tmp_path: Path,
) -> None:
    theory_file = tmp_path / "Example.thy"
    theory_file.write_text(
        "theory Example imports Main begin end\n",
        encoding="utf-8",
    )

    model_file = tmp_path / "model.json"
    model_file.write_text(
        json.dumps(
            {
                "metadata": {
                    "run_id": "variant-1",
                    "theory_name": "Example",
                },
                "model": {
                    "logic": "sdl",
                    "kind": "countermodel",
                    "cardinality": 3,
                    "relation": "R",
                    "designated_world": {
                        "index": 0,
                        "name": "i1",
                        "role": "initial_world",
                    },
                    "atoms": ["p"],
                    "edges": [[0, 1], [1, 2]],
                    "valuations": {
                        "p": [True, False, True],
                    },
                    "warnings": [],
                },
            }
        ),
        encoding="utf-8",
    )

    report_file = tmp_path / "report.json"

    result = launch_analysis(
        [model_file],
        theory_path=theory_file,
        output_path=report_file,
    )

    report = json.loads(
        report_file.read_text(encoding="utf-8")
    )

    assert result["status"] == "completed"
    assert result["model_count"] == 1
    assert result["highlight"]["basis"] == "pattern"
    assert report["theory"]["name"] == "Example"
    assert (
        report["clusters"][0]["representative_model"]["model_id"]
        == "variant-1"
    )