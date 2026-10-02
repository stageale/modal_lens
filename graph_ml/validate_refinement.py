"""Independently check exact pattern exclusion in an existing refinement run.

Uses the original model JSON, every injective world assignment, complete
valuations and positive AND negative relation cells. No clustering or graph
canonicalisation code is reused. This is a bounded data check, not an Isabelle
proof or a satisfiability check. Only the Python standard library is required.
"""
from __future__ import annotations

import argparse
import json
from itertools import permutations
from pathlib import Path


def occurrence_witness(model: dict, occurrence: dict) -> dict | None:
    worlds = occurrence["worlds"]
    ids = [world["id"] for world in worlds]
    if (occurrence["pairwise_distinct"] is not True
            or len(ids) != occurrence["size"] or len(set(ids)) != len(ids)):
        raise ValueError("Expected pairwise distinct candidate worlds.")
    cells = occurrence["relation_cells"]
    keys = {(cell["relation"], cell.get("agent")) for cell in cells}
    for key in keys:
        matrix = [cell for cell in cells
                  if (cell["relation"], cell.get("agent")) == key]
        if (len(matrix) != len(ids) ** 2
                or {(cell["source"], cell["target"]) for cell in matrix}
                != set(permutations(ids, 2)) | {(world, world) for world in ids}
                or any(type(cell["holds"]) is not bool for cell in matrix)):
            raise ValueError("Expected a complete Boolean relation matrix.")
    if not keys:
        raise ValueError("Candidate has no relation matrix.")

    if "modalities" in model:
        relations = {
            (modality["symbol"], modality.get("agent")):
            set(map(tuple, modality["accessibility"]))
            for modality in model["modalities"]
        }
    else:
        relations = {(model["relation"], None): set(map(tuple, model["edges"]))}
    if keys - relations.keys():
        raise ValueError(f"Model is missing candidate relations: {keys - relations.keys()}")
    valuations = model["valuations"]
    for world in worlds:
        for atom, value in world["valuations"].items():
            if type(value) is not bool or atom not in valuations:
                raise ValueError(f"Missing or invalid candidate valuation: {atom}")
            if (len(valuations[atom]) != model["cardinality"]
                    or any(type(item) is not bool for item in valuations[atom])):
                raise ValueError(f"Invalid model valuation: {atom}")

    for assignment in permutations(range(model["cardinality"]), len(worlds)):
        binding = dict(zip(ids, assignment))
        if not all(valuations[atom][binding[world["id"]]] == value
                   for world in worlds for atom, value in world["valuations"].items()):
            continue
        if all(((binding[cell["source"]], binding[cell["target"]])
                in relations[(cell["relation"], cell.get("agent"))]) == cell["holds"]
               for cell in cells):
            return binding
    return None


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _population(base: Path, expected: int) -> list[tuple[Path, dict]]:
    paths = sorted(base.glob("cardinality_*/iteration_*/model.json"))
    # Also support the older single-cardinality output layout.
    if not paths:
        paths = sorted(base.glob("iteration_*/model.json"))
    if len(paths) != expected:
        raise ValueError(f"Expected {expected} model files in {base}; found {len(paths)}.")
    return [(path, _read(path)["model"]) for path in paths]


def validate_run(base: str | Path) -> dict:
    base = Path(base).resolve()
    report = _read(base / "refinement.json")
    stages = []
    before_dir = base
    for iteration in report["iteration"]:
        occurrence = iteration["candidate"]["occurrence"]
        analysis = _read(before_dir / "report.json")
        before = _population(before_dir, iteration["enumeration_before"]["model_count"])
        after_dir = base / "refinement" / f"round-{iteration['round']:03d}"
        after = _population(after_dir, iteration["enumeration_after"]["model_count"])
        cluster = next(item for item in analysis["clusters"]
                       if item["cluster_id"] == iteration["cluster_id"])
        if len(cluster["model_indices"]) != cluster["model_count"]:
            raise ValueError("Cluster membership count is inconsistent.")
        if len(analysis["highlights"]) != len(before):
            raise ValueError("Analysis model count is inconsistent.")
        before_hits = {}
        after_hits = []
        for index, (path, model) in enumerate(before):
            witness = occurrence_witness(model, occurrence)
            if witness is not None:
                before_hits[index] = witness
        for path, model in after:
            witness = occurrence_witness(model, occurrence)
            if witness is not None:
                after_hits.append({"model": str(path.relative_to(base)), "witness": witness})
        cluster_members = cluster["model_indices"]
        target_hits = sum(index in before_hits for index in cluster_members)
        measured_support = target_hits / len(cluster_members) if cluster_members else 0.0
        support_matches = abs(measured_support - iteration["cluster_support"]) < 1e-12
        stages.append({
            "round": iteration["round"],
            "candidate_id": iteration["candidate_id"],
            "target_cluster_id": iteration["cluster_id"],
            "target_cluster_model_count": len(cluster_members),
            "target_cluster_models_containing_pattern": target_hits,
            "all_observed_target_members_excluded": target_hits == len(cluster_members),
            "recorded_cluster_support": iteration["cluster_support"],
            "measured_cluster_support": measured_support,
            "support_matches": support_matches,
            "before_model_count": len(before),
            "before_models_containing_pattern": len(before_hits),
            "outside_cluster_models_containing_pattern": len(before_hits) - target_hits,
            "after_model_count": len(after),
            "after_models_containing_pattern": len(after_hits),
            "after_enumeration_status": iteration["enumeration_after"]["status"],
            "violations": after_hits,
            "status": "passed" if not after_hits and support_matches and before_hits else "failed",
        })
        before_dir = after_dir
    return {
        "schema": "modal-lens/refinement-validation",
        "schema_version": "1.0",
        "run": base.name,
        "batch": base.parent.name,
        "status": ("not_applied" if not stages else
                   "passed" if all(stage["status"] == "passed" for stage in stages) else "failed"),
        "method": "all_injective_assignments_on_original_model_json",
        "scope": "stored_bounded_countermodel_population",
        "rounds": stages,
        "limitations": [
            "Cluster identities are local to each analysis; cluster numbers cannot be compared across rounds.",
            "Exclusion of a pattern covers all models satisfying the added axiom, but cluster coverage is measured on observed members only.",
            "This check does not establish satisfiability or entailment of the original query.",
        ],
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_directory")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args(argv)
    result = validate_run(arguments.run_directory)
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    return 1 if result["status"] == "failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
