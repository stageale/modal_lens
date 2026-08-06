# Reproducibility

## Reproducibility goal

A ModalLens run should be reproducible at the level of:

- source revision;
- dependency resolution;
- Isabelle theory and finite search configuration;
- canonical run parameters;
- generated model and analysis artifacts;
- verbalisation inputs and provenance.

Exact language-model wording may still vary across backend implementations and hardware.

## Environment record

For every published evaluation, record:

```text
Git commit
Operating system
Elixir version
Erlang/OTP version
Python version
uv.lock checksum
Isabelle version
Graphviz version
LaTeX engine version
Selected model logic
Enumeration mode
Nitpick scope and timeout
Maximum model count
Feature method
Graphlet size
Clustering configuration
Verbalisation backend and model revision
Seed and generation parameters
Hardware and numerical precision
```

The Python project currently requires Python `>=3.12,<3.13`.

## Locked dependencies

Install Python dependencies through the lock file:

```bash
uv sync --locked --group dev
```

Run Python tests through the locked environment:

```bash
uv run --locked python -m pytest -v
```

Elixir dependencies are resolved through Mix:

```bash
mix deps.get
mix deps.compile
```

A public artifact should include `mix.lock` and `uv.lock`.

## Isabelle setup

Prepare the user heap:

```bash
./cmd/setup_isabelle.sh
```

When Isabelle is not on `PATH`:

```bash
MODALLENS_ISABELLE_BIN=/path/to/isabelle \
  ./cmd/setup_isabelle.sh
```

Record the exact Isabelle executable and version:

```bash
/path/to/isabelle version
```

The generated search theories import the unchanged base theory and accumulate blocking axioms. Preserve the generated theories when auditing enumeration behaviour.

## Test commands

Full suite:

```bash
mix test.all
```

Elixir only:

```bash
MIX_ENV=test mix test
mix compile --warnings-as-errors
mix format --check-formatted
```

Python only:

```bash
uv run --locked python -m pytest -v
uv run python -m compileall graph_ml verbalization
```

Formatting:

```bash
uv run ruff format --check graph_ml verbalization test/python
```

## Reference demo

Use a bounded, non-verbalised run for the primary smoke test:

```bash
rm -rf out/reproducibility/sdl

./modal_lens demo examples/input/Chisholm.thy \
  -o out/reproducibility/sdl \
  --model-logic sdl \
  --max-models 5 \
  --graph-format svg \
  --palette turbo \
  --no-verbalize
```

Run DDL separately:

```bash
rm -rf out/reproducibility/ddl

./modal_lens demo examples/input/Dyadic_Chisholm.thy \
  -o out/reproducibility/ddl \
  --model-logic ddl \
  --max-models 5 \
  --graph-format svg \
  --palette turbo \
  --no-verbalize
```

A run may terminate before the maximum if no further model is found.

## Artifacts to preserve

Preserve the complete output directory, not only the HTML page:

```text
run.json
report.json
all model-N directories
generated search theories
cluster-scoped verbalisation reports
verbalization_request.json
raw_output.txt
summary.json
summary.md
provenance.json
```

Also preserve:

```text
README.md
docs/
mix.exs
mix.lock
pyproject.toml
uv.lock
example theories
```

## Deterministic stages

Under fixed software and input, the following stages are intended to be deterministic:

- parsing a stored Nitpick result;
- model JSON export;
- blocking-axiom generation;
- graph construction;
- feature extraction;
- clustering under the same library implementation;
- pattern mining;
- report construction, except timestamps;
- fact extraction and canonical hashing;
- prompt message construction.

Potential sources of variation include:

- Isabelle/Nitpick search behaviour across versions or settings;
- floating-point and clustering-library differences;
- report timestamps;
- language-model inference;
- backend-specific sampling and device kernels.

## Comparing runs

Do not compare entire output directories byte-for-byte without normalisation. Instead compare:

- schema identifiers and versions;
- model count and finite model content;
- blocking axioms;
- cluster membership;
- characteristic-pattern identifiers and metrics;
- highlights;
- fact and message hashes;
- run parameters and tool versions.

Timestamps, absolute paths, runtime metrics, and generated wording may require separate treatment.

## Failure records

Failed runs should retain `run.json` with:

- failed status;
- structured reason;
- runtime metric;
- artifacts successfully written before failure.

This is preferable to deleting partial output because it preserves the failing boundary for diagnosis.
