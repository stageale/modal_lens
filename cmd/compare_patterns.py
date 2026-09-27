#!/usr/bin/env python3
"""Compare characteristic graphlets from two ModalLens analysis reports.

The default comparison reports both exact attributed matches and matches of
relation topology after proposition labels are ignored. The latter is useful
for checking whether two case studies share a frame pattern without claiming
that their attributed graphlets are semantically identical.
"""

from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path
from typing import Any


def patterns(report: dict[str, Any]) -> list[dict[str, Any]]:
    result = []
    for cluster in report.get("clusters", []):
        for pattern in cluster.get("characteristic_patterns", []):
            result.append(
                {
                    "cluster_id": cluster.get("cluster_id"),
                    "pattern_id": pattern.get("pattern_id"),
                    "support": pattern.get("cluster_support"),
                    "contrast": pattern.get("contrast"),
                    "pattern": pattern.get("pattern"),
                }
            )
    return result


def edge_matrix(pattern: list[Any]) -> tuple[int, tuple[int, ...]]:
    _, size, data = pattern
    _node_labels, edges = data
    return int(size), tuple(int(cell[0]) for cell in edges)


def canonical_topology(pattern: list[Any]) -> tuple[int, tuple[int, ...]]:
    size, matrix = edge_matrix(pattern)
    variants = []
    for order in itertools.permutations(range(size)):
        variants.append(
            tuple(matrix[i * size + j] for i in order for j in order)
        )
    return size, min(variants)


def short(item: dict[str, Any]) -> str:
    return (
        f"cluster={item['cluster_id']} {item['pattern_id']} "
        f"support={item['support']:.3f} contrast={item['contrast']:.3f}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report_a", type=Path)
    parser.add_argument("report_b", type=Path)
    args = parser.parse_args()

    report_a = json.loads(args.report_a.read_text(encoding="utf-8"))
    report_b = json.loads(args.report_b.read_text(encoding="utf-8"))
    patterns_a = patterns(report_a)
    patterns_b = patterns(report_b)

    exact = []
    structural = []

    for left in patterns_a:
        for right in patterns_b:
            if left["pattern"] == right["pattern"]:
                exact.append((left, right))
            elif canonical_topology(left["pattern"]) == canonical_topology(right["pattern"]):
                structural.append((left, right))

    print(f"A: {args.report_a} ({len(patterns_a)} characteristic patterns)")
    print(f"B: {args.report_b} ({len(patterns_b)} characteristic patterns)")
    print()
    print(f"Exact attributed matches: {len(exact)}")
    for left, right in exact:
        print(f"  {short(left)}  <->  {short(right)}")

    print()
    print(f"Same relation topology, different valuations/labels: {len(structural)}")
    for left, right in structural:
        print(f"  {short(left)}  <->  {short(right)}")
        print(f"    A valuations: {left['pattern'][2][0]}")
        print(f"    B valuations: {right['pattern'][2][0]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
