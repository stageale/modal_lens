from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from typing import Any, Literal, TypeAlias, TypedDict

EdgeCell: TypeAlias = tuple[int, str | None]
NodeLabels: TypeAlias = tuple[tuple[str, ...], ...]
DecodedGraphlet: TypeAlias = tuple[int, NodeLabels, tuple[EdgeCell, ...]]


class ValuedWorld(TypedDict):
    """One abstract graphlet world with its complete valuation."""
    id: str
    valuations: dict[str, bool]

class RelationCell(TypedDict):
    """One positive or negative cell of the induced relation matrix."""
    source: str
    target: str
    relation: str
    holds: bool

class OccurrenceSpec(TypedDict):
    """A complete existential occurence of an induced graphlet."""
    size: int
    pairwise_distinct: bool
    worlds: list[ValuedWorld]
    relation_cells: list[RelationCell]

class PatternOrigin(TypedDict):
    """Cluster evidence from which the candidate was constructed."""
    pattern_id: str
    cluster_id: int
    rank: int
    cluster_support: float
    outside_support: float
    contrast: float

class NegationSpec(TypedDict):
    """The structural transformation applied to the occurrence."""
    rule: Literal["exclude_exact_induced_occurrence"]
    operator: Literal["not"]
    operand: Literal["occurrence"]

class RefinementCandidate(TypedDict):
    """A language-neutral structural refinement candidate."""
    schema: Literal["modal-lens/refinement-candidate"]
    schema_version: Literal["1.0"]
    candidate_id: str
    kind: Literal["exact_induced_graphlet_exclusion"]
    status: Literal["candidate"]
    origin: PatternOrigin
    occurrence: OccurrenceSpec
    refinement: NegationSpec

def _normalize_atoms(atoms: Sequence[str]) -> tuple[str, ...]:
    """Validate and deterministically order the proposition signature."""

    if isinstance(atoms, (str, bytes)):
        raise TypeError("Atoms must be a sequence of proposition names.")

    normalized = tuple(atoms)

    if any(not isinstance(atom, str) or not atom.strip() for atom in normalized):
        raise ValueError("Every proposition name must be a non-empty string.")

    if len(set(normalized)) != len(normalized):
        raise ValueError("Proposition names must be unique.")

    return tuple(sorted(normalized))

def _decode_graphlet(pattern: Any, *, atoms: tuple[str, ...], relation: str) -> DecodedGraphlet:
    """Validate and decode one canonical single-relation graphlet."""

    if not isinstance(pattern, Sequence) or isinstance(pattern, (str, bytes)):
        raise TypeError("Pattern must be a graphlet sequence.")

    if len(pattern) != 3:
        raise ValueError("A graphlet pattern must contain tag, size, and payload.")

    tag, size, payload = pattern

    if tag != "graphlet":
        raise ValueError(f"Unsupported pattern kind: {tag!r}")

    if isinstance(size, bool) or not isinstance(size, int) or size < 1:
        raise ValueError("Graphlet size must be a positive integer.")

    if not isinstance(payload, Sequence) or isinstance(payload, (str, bytes)):
        raise TypeError("Graphlet payload must be a sequence.")

    if len(payload) != 2:
        raise ValueError("Graphlet payload must contain node labels and edges.")

    raw_node_labels, raw_edges = payload

    if(
        not isinstance(raw_node_labels, Sequence)
        or isinstance(raw_node_labels, (str, bytes))
        or len(raw_node_labels) != size
    ):
        raise ValueError("Node-label count must equal the graphlet size.")

    atom_set = set(atoms)
    node_labels: list[tuple[str, ...]] = []

    for world_index, raw_labels in enumerate(raw_node_labels):
        if not isinstance(raw_labels, Sequence) or isinstance(raw_labels, (str, bytes)):
            raise TypeError(f"Labels of graphlet world {world_index} must be a sequence.")
        labels = tuple(raw_labels)
        if any(not isinstance(label, str) for label in labels):
            raise TypeError("Graphlet proposition labels must be strings.")
        if len(set(labels)) != len(labels):
            raise ValueError(f"Graphlet world {world_index} contains duplicate labels.")

        unknown_atoms = set(labels) - atoms

        if unknown_atoms:
            raise ValueError("Graphlet contains propositions outside the supplied signature: "
                             f"{sorted(unknown_atoms)!r}")

        node_labels.append(labels)

    if(
        not isinstance(raw_edges, Sequence)
        or isinstance(raw_edges, (str, bytes))
        or len(raw_edges) != size * size
    ):
        raise ValueError("The induced relation matrix must contain exactly size² cells.")

    edges: list[EdgeCell] = []

    for cell_index, raw_cell in enumerate(raw_edges):
        if(
            not isinstance(raw_cell, Sequence)
            or isinstance(raw_cell, (str, bytes))
            or len(raw_cell) != 2
        ):
            raise ValueError(f"Relation cell {cell_index} must contain state and label.")

        state, label = raw_cell

        if isinstance(state, bool) or not isinstance(state, int) or state not in (0, 1):
            raise ValueError(f"Relation cell {cell_index} must have state 0 or 1.")

        if state == 1 and label != relation:
            raise ValueError(
                "The graphlet is not compatible with the supplied " \
                f"single relation {relation!r}."
            )

        if state == 0 and label is not None:
            raise ValueError(f"Negative relation cell {cell_index} must not carry a label.")

        edges.append((state, label))

    return size, tuple(node_labels), tuple(edges)

def _score(value: Any, *, name: str, lower: float, upper: float) -> float:
    """Validate one finite cluster-evidence score."""

    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise TypeError(f"{name} must be numeric.")

    normalized = float(value)

    if not math.isfinite(normalized):
        raise ValueError(f"{name} must be finite.")

    if not lower <= normalized <= upper:
        raise ValueError(
            f"{name} must be between {lower} and {upper}."
        )

    return normalized

def derive_exclusion_candidate(pattern_data: Mapping[str, Any], *, cluster_id: int, rank: int, atoms: Sequence[str], relation: str) -> RefinementCandidate:
    """
    Construct the negation of an exact induced graphlet occurrence.
    
    The result is a language-neutral structural candidate. It does not assign 
    a modal frame property, claim logical validity, or render Isabelle syntax.
    """
    if isinstance(cluster_id, bool) or not isinstance(cluster_id, int):
        raise TypeError("Cluster ID must be an integer.")

    if isinstance(rank, bool) or not isinstance(rank, int) or rank < 1:
        raise ValueError("Pattern rank must be a positive integer.")

    if not isinstance(relation, str) or not relation.strip():
        raise ValueError("Relation name must be a non-empty string.")

    normalized_atoms = _normalize_atoms(atoms)

    size, node_labels, edge_cells = _decode_graphlet(pattern_data.get("pattern"), atoms=normalized_atoms, relation=relation)

    pattern_id = f"cluster-{cluster_id}-pattern-{rank}"
    world_ids = [f"u{index}" for index in range(1, size + 1)]

    worlds: list[ValuedWorld] = []

    for world_id, true_atoms in zip(world_ids, node_labels, strict=True):
        true_atom_set = set(true_atoms)
        worlds.append(
            {
                "id": world_id,
                "valuations": {
                    atom: atom in true_atom_set
                    for atom in normalized_atoms
                }
            }
        )

    relation_cells: list[RelationCell] = []

    for cell_index, (state, _label) in enumerate(edge_cells):
        source_index, target_index = divmod(cell_index, size)

        relation_cells.append(
            {
                "source": world_ids[source_index],
                "target": world_ids[target_index],
                "relation": relation,
                "holds": state == 1
            }
        )

    return {
        "schema": "modal-lens/refinement-candidate",
        "schema_version": "1.0",
        "candidate_id": f"refinement-{pattern_id}",
        "kind": "exact_induced_graphlet_exclusion",
        "status": "candidate",
        "origin": {
            "pattern_id": pattern_id,
            "cluster_id": cluster_id,
            "rank": rank,
            "cluster_support": _score(
                pattern_data.get("cluster_support"),
                name="cluster_support",
                lower=0.0,
                upper=1.0
            ),
            "outside_support": _score(
                pattern_data.get("outside_support"),
                name="outside_support",
                lower=0.0,
                upper=1.0,
            ),
            "contrast": _score(
                pattern_data.get("contrast"),
                name="contrast",
                lower=-1.0,
                upper=1.0
            )
        },
        "occurrence": {
            "size": size,
            "pairwise_distinct": True,
            "worlds": worlds,
            "relation_cells": relation_cells
        },
        "refinement": {
            "rule": "exclude_exact_induced_occurrence",
            "operator": "not",
            "operand": "occurrence"
        }
    }