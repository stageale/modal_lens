# Reviewer guide

## Purpose

ModalLens is a research prototype for inspecting finite models and countermodels of modal specifications. It connects Isabelle/Nitpick model generation with graph-based structural analysis, visual evidence, and optional natural-language verbalisation.

The prototype is intended to answer the practical question:

> How can a collection of finite semantic structures be made inspectable in a reproducible, machine-readable, and human-reviewable workflow?

It does not yet claim to automate the normative decision of which new axiom should be accepted.

## What to review

The current prototype contribution is the integrated workflow:

```text
Isabelle theory
→ iterative finite-model enumeration
→ versioned model artifacts
→ structural feature extraction
→ clustering and characteristic-pattern mining
→ evidence highlighting
→ optional fact-grounded verbalisation
→ HTML review interface
```

The key design properties are:

- **one canonical execution pipeline** rather than separate CLI and UI implementations;
- **blocking-axiom enumeration** that preserves each discovered finite structure;
- **durable JSON contracts** between Elixir and Python;
- **separation of deterministic evidence from generative wording**;
- **artifact and provenance preservation** for post-hoc inspection.

## Fastest reproducible review

Build the project:

```bash
mix deps.get
uv sync --group dev
mix compile
mix escript.build
```

Run the test suites:

```bash
mix test.all
```

Run a lightweight demo without verbalisation:

```bash
./modal_lens demo examples/input/Chisholm.thy \
  -o out/reviewer-demo \
  --model-logic sdl \
  --max-models 5 \
  --graph-format svg \
  --palette turbo \
  --no-verbalize
```

Open:

```bash
xdg-open out/reviewer-demo/index.html
```

## Suggested inspection points

### Symbolic boundary

Inspect:

```text
lib/src/isabelle/
lib/src/enumeration/
lib/src/core/parser.ex
lib/src/core/blocking_axiom.ex
```

Questions answered there:

- How is Isabelle invoked?
- How is a Nitpick result parsed?
- How is a discovered model excluded from later iterations?
- How are SDL and DDL model differences represented?

### Execution and artifact boundary

Inspect:

```text
lib/src/execution/
lib/src/serialization.ex
```

Questions answered there:

- Which component owns the run lifecycle?
- Which options are canonical?
- Where are artifact paths registered and persisted?
- Which JSON documents are accepted or rejected?

### Graph-analysis boundary

Inspect:

```text
graph_ml/io_schema.py
graph_ml/features.py
graph_ml/clustering.py
graph_ml/mining.py
graph_ml/report.py
graph_ml/launcher.py
```

Questions answered there:

- Which model fields become a graph?
- Which feature families are available?
- How are clusters selected?
- What makes a pattern characteristic of a cluster?
- How are highlights attached to durable reports?

### Explanation boundary

Inspect:

```text
lib/src/explanation/
verbalization/
```

Questions answered there:

- How are highlights rendered?
- Which facts reach the language model?
- How is the model response validated?
- Which provenance is retained?

## Interpreting the result

A cluster is an empirical grouping under the selected feature representation and clustering procedure. A characteristic pattern is a recurring graphlet with support and contrast under the current finite sample. A highlight links such evidence back to specific worlds and edges.

None of these objects is, by itself:

- a logical proof;
- a completeness result;
- a normative recommendation;
- a guarantee that an omitted model does not exist.

The verbal summary is additionally constrained to describe recorded facts, but it remains generated text and should be reviewed against `report.json` and `provenance.json`.

## Scope of evaluation

For a prototype review, the strongest claims are architectural and reproducibility-oriented:

- finite-model results are preserved as explicit artifacts;
- cross-language boundaries are versioned and validated;
- deterministic analysis can be inspected independently of verbalisation;
- the same canonical pipeline supports the review interface.

Broader empirical claims about clustering quality, model choice, and refinement effectiveness require a dedicated benchmark design and are outside the current prototype validation.
