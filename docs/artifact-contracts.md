# Artifact contracts

## Purpose

ModalLens uses durable JSON documents as the cross-language boundary between Elixir and Python. These artifacts are intended to remain inspectable after the producing process exits.

The current implementation still uses the schema prefix `axiom-refiner/`. A rename to `modallens/` should be performed atomically before the first public release, together with tests and fixtures. Do not publish documentation with one prefix while the code emits another.

## Contract summary

| Artifact | Current schema | Version | Producer | Consumer |
|---|---|---:|---|---|
| Finite model | `axiom-refiner/model` | `1.0` | Elixir enumeration | Python graph analysis |
| Analysis report | `axiom-refiner/analysis-report` | `1.0` | Python graph analysis | Elixir pipeline, Python verbalisation |
| Graph-analysis result | `axiom-refiner/graph-analysis-result` | `1.0` | Python launcher stdout | Elixir pipeline |
| Verbalisation request | `axiom-refiner/verbalization-request` | `1.0` | Elixir verbal launcher | Python verbalisation launcher |
| Verbalisation summary | `axiom-refiner/verbalization-summary` | `1.0` | Python verbalisation pipeline | Elixir pipeline, reviewers |
| Verbalisation provenance | `axiom-refiner/verbalization-provenance` | `1.0` | Python verbalisation pipeline | Reviewers and evaluation scripts |

Schema versions are strings. Numeric and string versions are not interchangeable.

## Finite model

Minimal envelope:

```json
{
  "schema": "axiom-refiner/model",
  "schema_version": "1.0",
  "metadata": {
    "iteration": 1,
    "mode": "countermodels",
    "theory_name": "Example",
    "base_theory_file": "Example.thy",
    "search_theory_file": "Example_Search_001.thy"
  },
  "artifacts": {
    "nitpick_output": "nitpick.txt",
    "json": "model.json",
    "dot": "model.dot",
    "svg": "model.svg",
    "tikz": "model.tex",
    "pdf": null,
    "blocking_axiom": "blocking_axiom.thyfrag"
  },
  "model": {
    "logic": "sdl",
    "kind": "countermodel",
    "cardinality": 2,
    "relation": "R",
    "designated_world": {
      "index": 0,
      "name": "i1",
      "role": "initial_world"
    },
    "atoms": ["p"],
    "edges": [[0, 1]],
    "valuations": {
      "p": [true, false]
    },
    "warnings": []
  }
}
```

Required reader assumptions:

- the document is a JSON object;
- schema and version match exactly;
- `metadata` and `model` are objects;
- graph-relevant model fields are well-typed.

Graph artifacts may be `null` when rendering is disabled.

## Analysis report

Minimal envelope:

```json
{
  "schema": "axiom-refiner/analysis-report",
  "schema_version": "1.0",
  "generated_at": "2026-08-06T00:00:00+00:00",
  "purpose": "normative_gap_analysis",
  "scope": {
    "goal": "Identify recurring structural indicators of possible normative gaps.",
    "creates_new_norms": false,
    "refinement_role": "diagnostic_support_for_human_deliberation"
  },
  "theory": {
    "name": "Example"
  },
  "analysis": {
    "model_count": 1,
    "cluster_count": 1,
    "reported_pattern_count": 0
  },
  "clusters": [],
  "highlights": []
}
```

`report.json` is the authoritative source for cluster and highlight data. The graph-analysis subprocess does not duplicate highlights in stdout.

Cluster-specific verbalisation reports retain the same schema but contain only the selected cluster and the highlights belonging to its model indices.

## Graph-analysis result

This is a minimal process response, not the durable analysis artifact:

```json
{
  "schema": "axiom-refiner/graph-analysis-result",
  "schema_version": "1.0",
  "status": "completed",
  "report_path": "/absolute/path/report.json",
  "model_count": 5,
  "cluster_count": 2,
  "feature_method": "combined",
  "graphlet_size": 3
}
```

Elixir validates the envelope and then opens `report_path`. It does not accept a missing report path or silently substitute a fallback for a malformed response.

## Verbalisation request

```json
{
  "schema": "axiom-refiner/verbalization-request",
  "schema_version": "1.0",
  "backend": "transformers",
  "model_id": "HuggingFaceTB/SmolLM3-3B",
  "report_path": "/absolute/path/report.json",
  "output_directory": "/absolute/path/verbalization/cluster-0",
  "seed": 42,
  "max_new_tokens": 768,
  "backend_options": {}
}
```

The request references the report artifact rather than embedding report contents.

## Verbalisation summary

```json
{
  "schema": "axiom-refiner/verbalization-summary",
  "schema_version": "1.0",
  "overview": "Summary of the analysed structures.",
  "cluster_summaries": [
    {
      "cluster_id": 0,
      "summary": "Description grounded in the supplied facts.",
      "notable_patterns": [],
      "evidence": []
    }
  ],
  "limitations": []
}
```

The model-generated content is parsed and validated before this artifact is written. Unknown or malformed structures are rejected rather than stored as accepted summaries.

## Verbalisation provenance

```json
{
  "schema": "axiom-refiner/verbalization-provenance",
  "schema_version": "1.0",
  "backend": "transformers",
  "model_id": "HuggingFaceTB/SmolLM3-3B",
  "seed": 42,
  "max_new_tokens": 768,
  "verbalization_facts_sha256": "...",
  "messages_sha256": "...",
  "raw_output_sha256": "...",
  "backend_metadata": {}
}
```

The hashes allow later checks that the recorded facts, messages, and raw output match the retained run artifacts.

## Run manifest

`run.json` is an Elixir-owned manifest rather than a Python exchange contract. It records:

- run identifier and status;
- canonical parameters;
- registered artifact paths;
- provenance;
- runtime metrics;
- structured failure information, when applicable.

Artifact paths must resolve inside the run output directory. Paths that escape the output root are rejected.

## Versioning policy

Before the first stable release:

- breaking field changes may increment the schema version;
- a project-prefix rename may be performed once, atomically;
- fixtures and both language-side validators must change in the same commit.

After a stable release:

- adding optional fields is a minor compatible change;
- removing or changing required fields requires a new schema version;
- readers should reject unknown major contracts instead of guessing;
- historical artifacts should remain interpretable through documented migration code or retained readers.
