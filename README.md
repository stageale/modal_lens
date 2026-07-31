# Axiom Refiner

**Countermodel-guided iterative axiom refinement for modal and higher-order logic experiments**

Axiom Refiner is a research prototype that combines:

* Isabelle/HOL and Nitpick for countermodel generation
* Elixir for orchestration, enumeration, and artifact management
* Python for graph analysis, clustering, and pattern extraction
* Graphviz and TikZ for countermodel visualization
* Small language models for optional verbal explanations

The prototype currently supports standard deontic logic (SDL) and dyadic deontic logic (DDL).

## Requirements

The local development environment requires:

* Elixir `~> 1.19`
* Erlang/OTP compatible with the selected Elixir version
* Python `3.12`
* [`uv`](https://docs.astral.sh/uv/)
* Isabelle/HOL
* Graphviz
* A LaTeX installation for TikZ and PDF artifacts

Docker can optionally be used for the Elixir and Python environment. Isabelle currently remains a host-side dependency.

## Installation

Clone the repository and enter the project directory:

```bash
git clone <repository-url>
cd axiom_refiner
```

Install the Elixir dependencies:

```bash
mix deps.get
```

Install the Python environment and development dependencies:

```bash
uv sync --group dev
```

Prepare the Isabelle/HOL user heap:

```bash
./cmd/setup_isabelle.sh
```

When Isabelle is not available through `PATH`, provide its executable explicitly:

```bash
AXIOM_REFINER_ISABELLE_BIN=/path/to/isabelle \
  ./cmd/setup_isabelle.sh
```

Compile the project:

```bash
mix compile
```

Build the command-line executable:

```bash
mix escript.build
```

This creates the local executable:

```text
./axiom_refiner
```

## Demo

The bundled demo command supports SDL and DDL examples with either SVG or TikZ selected as the displayed graph format.

### SDL with SVG

```bash
./cmd/demo.sh sdl no
```

### SDL with TikZ

```bash
./cmd/demo.sh sdl yes
```

### DDL with SVG

```bash
./cmd/demo.sh ddl no
```

### DDL with TikZ

```bash
./cmd/demo.sh ddl yes
```

Run all four configurations:

```bash
./cmd/demo.sh all
```

Additional command-line options are forwarded to the Axiom Refiner executable:

```bash
./cmd/demo.sh ddl yes --verbalize
```

```bash
./cmd/demo.sh sdl no --palette viridis
```

The DDL example is defined in:

```text
examples/input/Dyadic_Chisholm.thy
```

It imports:

```text
examples/input/E.thy
```

The Isabelle integration resolves this import automatically. `E.thy` does not need to be passed separately to the demo command.

## Direct CLI usage

The same examples can be executed without the wrapper script.

### SDL

```bash
./axiom_refiner demo \
  examples/input/Chisholm.thy \
  -o out/demo_sdl \
  --model-logic sdl \
  --palette turbo \
  --graph-format svg
```

### DDL

```bash
./axiom_refiner demo \
  examples/input/Dyadic_Chisholm.thy \
  -o out/demo_ddl \
  --model-logic ddl \
  --palette turbo \
  --graph-format svg
```

Available command-line options can be inspected with:

```bash
./axiom_refiner help
```

or:

```bash
./axiom_refiner demo --help
```

## Testing

Run the complete Elixir and Python test suite with:

```bash
mix test.all
```

This invokes:

```text
cmd/test_all.sh
```

The suites can also be executed separately.

### Elixir

```bash
MIX_ENV=test mix test
```

### Python

```bash
uv run --locked python -m pytest -v
```

Check Elixir formatting with:

```bash
mix format --check-formatted
```

## Docker

Build the development image:

```bash
docker build -t axiom-refiner .
```

Run the configured test command:

```bash
docker run --rm axiom-refiner
```

The `.dockerignore` file excludes local build artifacts, dependency directories, generated output, caches, and runtime files from the Docker build context.

## Project structure

```text
axiom_refiner/
├── cmd/                  Project commands and setup scripts
├── examples/             Isabelle theories and example inputs
├── graph_ml/             Python graph-analysis implementation
├── lib/                  Elixir source code
├── priv/                 Project resources and static assets
├── test/                 Elixir and Python tests
├── Dockerfile
├── mix.exs
├── pyproject.toml
└── uv.lock
```

The current Elixir implementation is divided broadly into:

```text
Src.Core
Src.Explanation
Src.Interface
Src.ModelEnumeration
```

This structure is being consolidated as part of the ongoing refactoring. The current executable entry point remains:

```elixir
Src.Interface.CLI
```

## Generated artifacts

Depending on the selected options, a run can generate:

* Parsed countermodel JSON
* DOT graph descriptions
* SVG visualizations
* TikZ source
* PDF visualizations
* Blocking axioms
* Enumeration metadata
* Graph-analysis reports
* Cluster and pattern information
* Verbal summaries

Generated files are written below the selected output directory and should not be committed to version control.

## Project status

Axiom Refiner is an active research prototype. Its internal modules and exchange formats are still being refactored and should not yet be treated as a stable public API.
