# ModalLens:  

## A Modal Semantics Explorer

#

ModalLens is a research prototype for enumerating, analysing, visualising, and explaining finite models and countermodels of modal logics.

It combines symbolic model generation in ATPs with graph-based structural analysis and optional language-model verbalization. The current prototype is developed in the context of the LogiKEy and LoDEx.

### Research scope

ModalLens is designed to support the inspection of finite semantic structures produced in context of a modal logical theory. Its curent workflow focuses on:

* enumerating distinct finite models or countermodels;
* preserving each result as a versioned machine-readable artifact;
* extracting graph features and recurring structural patterns;
* grouping related models through clustering;
* highlighting structural evidence in graph visualizations;
* optionally verbalizing deterministic analysis facts with a small language model;
* presenting the resulting evidence in an HTML review interface

Graph patterns, clusters, highlights, and verbal summaries are diagnostic evidence intended to support human-guided analysis and later axiom refinement


### Analysis pipeline

1. Isabelle theory
2. Isabelle/HOL and Nitpick
3. finite models or countermodels
4. versioned model JSON artifacts
5. graph features, clustering, and pattern mining
6. model-level highlights and analysis report
7. optional seeded verbalization
8. HTML review interface and run manifest

The Elixir application owns orchestration, model enumeration, run state, and artifact management. Python components perform graph analysis and optional verbalization. Durable JSON files, rather than subprocess output, form the exchange boundary between the components.

### Current capabilities

#### Supported modal frames

* Standard deontic logic (`sdl`)
* Dyadic deontic logic (`ddl`)

#### Supported world logics

* propositional logic

#### Enumeration modes

* `countermodels`: enumerate finite countermodels to a named query;
* `satisfying-models`: enumerate finite models satisfying the base theory;
* `consistency-check`: search for at most one finite model in configured Nitpick scope.

A failed finite consistency search is not a general proof of inconsistency.
It only reports that no model was found within the selected finite scope.

(But: For propositional modal logic satisfiability is equivalent to finite satisfiability, consider the guarded fragment for further explanation.)

#### Generated explanations

* Graphviz DOT and SVG output
* TikZ source and optional PDF output
* world- and edge-level structural highlights
* cluster and characteristic-pattern reports
* optional verbal summaries with provenance

The verbalization stage consumes deterministic report data. Generated natural-language text is treated as an explanation of recorded evidence, not as an independent source of logical or normative claims.

### Requirements

The local development environment requires:

* Elixir `1.19`;
* an Erlang/OTP release compatible with the selected Elixir version;
* Python `3.12`;
* Isabelle/HOL with Nitpick;
* Graphbiz for DOT/SVG rendering;
* a LaTeX installation for TikZ/PDF rendering

The optional transformers-based verbalization backend may require substantial memory and, depending on the selected model, GPU support. The symbolic and graph-analysis pipeline can be tested without verbalization.

Docker can be used for the Elixir and Python environemnt. Isabelle currently remains a host-side dependency.

### Installation

Clone the repository and enter the project directory:

`git clone <repository-url>`
`cd modal-lens`

Install the Elixir dependencies

`mix deps.get`

Install the locked Python environement and development dependencies:

`uv sync --group dev`

Prepare the Isabelle/HOL user heap:

`./cmd/setup_isabelle.sh`

When Isabelle is not available through `PATH`, provide its executable explicitly:

`MODALLENS_ISABELLE_BIN=/path/to/isabelle ./cmd/setup_isabelle.sh`

Compile the application and build the local command-line executable:

`mix compile`
`mix escript.build`

This creates:

`./modal_lens`

### Quick start

The following command runs the SDL example, enumerates at most five countermodels, performs graph analysis, renders SVG artifacts, and generates the HTML interface. Verbalization is disabled for a lightweight first run.

```
./modal_lens demo examples/input/Chisholm.thy \ 
  -o out/demo/sdl_svg \
  --model-logic sdl \
  --max-models 5 \
  --graph-format svg \
  --palette turbo \
  --no-verbalize
```

Open the generated interface:
`xdg-open out/demo/sdl_svg/index.html`

#### DDL example

```
./modal_lens demo examples/input/Chisholm.thy \ 
  -o out/demo/sdl_svg \
  --model-logic ddl \
  --max-models 5 \
  --graph-format svg \
  --palette turbo \
  --no-verbalize
```

The DDL example import `examples/input/E.thy`.
The Isabelle integration resolves the import from the base theory; `E.thy` is not supplied as a separate command-line input.

#### Enable verbalization

Verbalization is enabled by default in the demo workflow. Omit `--no-verbalize` and optionally select a model:

```
./modal_lens demo examples/input/Chisholm.thy \
  -o out/demo/sdl_verbalized \
  --model-logic sdl \
  --max-models 5 \
  --verbalization-model HuggingFaceTB/SmolLM3-3B
```



## Enumeration without the review interface

The lower-level enumeration command exposes the three model-search modes directly.

```bash
./modal_lens enumerate \
  --input examples/input/Chisholm.thy \
  --mode countermodels \
  --model-logic sdl \
  --max-models 5 \
  --out-dir out/enumeration/chisholm
```

Valid values for `--mode` are:

```text
countermodels
satisfying-models
consistency-check
```

Inspect the complete command-line help with:

```bash
./modal_lens help
```

## Generated artifacts

A completed run may contain:

```text
OUTPUT_DIR/
├── index.html
├── run.json
├── report.json
├── model-001/
│   ├── nitpick-output.txt
│   ├── model.json
│   ├── blocking-axiom.thy
│   ├── model.dot
│   ├── model.svg
│   ├── model.tex
│   └── model.pdf
├── model-002/
│   └── ...
└── verbalization/
    └── cluster-N/
        ├── request.json
        ├── report.json
        ├── raw_output.txt
        ├── summary.json
        ├── summary.md
        └── provenance.json
```

The exact set depends on the selected options. For example, `--no-render-graph` suppresses DOT, SVG, TikZ, and PDF generation while retaining model enumeration, graph analysis, and highlight data.

The durable exchange artifacts use explicit schema identifiers and schema versions. Generated output directories should not be committed to version control.

## Testing

Run the complete Elixir and Python test suite:

```bash
mix test.all
```

This invokes:

```text
cmd/test_all.sh
```

Run the suites separately when diagnosing failures.

### Elixir

```bash
MIX_ENV=test mix test
```

Compile with warnings treated as errors:

```bash
mix compile --warnings-as-errors
```

Check formatting:

```bash
mix format --check-formatted
```

### Python

```bash
uv run --locked python -m pytest -v
```

Format and statically compile the Python modules:

```bash
uv run ruff format graph_ml verbalization
uv run python -m compileall graph_ml verbalization
```

## Docker

Build the development image:

```bash
docker build -t modal-lens .
```

Run the configured test command:

```bash
docker run --rm modal-lens
```

The Docker image covers the Elixir and Python environments. Host-side Isabelle configuration is still required for full end-to-end model enumeration.

## Architecture

```text
modal-lens/
├── cmd/              setup, demo, and test commands
├── examples/         Isabelle example theories
├── graph_ml/         feature extraction, clustering, mining, and reports
├── lib/src/core/     logical models, parsing, and blocking axioms
├── lib/src/enumeration/
│                     iterative model enumeration and search theories
├── lib/src/execution/
│                     canonical pipeline, options, runs, and artifacts
├── lib/src/explanation/
│                     visual highlighting and verbalisation launchers
├── lib/src/interface/
│                     CLI and HTML review interface
├── lib/src/isabelle/
│                     local and HPC Isabelle adapters
├── verbalization/    facts, prompts, backends, and result artifacts
└── test/             Elixir and Python tests
```

The canonical end-to-end workflow is owned by the execution pipeline. User interfaces construct validated run options and delegate execution rather than implementing separate analysis paths.


### Reproducibility

ModalLens records run parameters, generated artifacts, provenance, and runtime measurements in `run.json`.

The implementation separates deterministic and generative stages:

* parsing, model export, graph analysis, cluster reports, and prompt facts are machine-generated artifacts;
* verbalization uses an explicit backend, model identifier, seed, and token limit;
* raw model output and provenance are preserved beside the validated summary;
* external model implementations and hardware may still affect exact generated wording

For evaluation runs; preserve the complete output directory together with the source revision, dependency lock files, Isabelle version, backend configuration, and selected model identifier.

### Limitations and development status

ModalLens is an active research prototype. The following limitations are intentional and should be considered when interpreting its output:

* model search is bounded by the configured Nitpic scope;
* current model parsers target the supported SDL and DDL representations;
* graph clusters and mined patterns are diagnostic summaries, not logical proofs;
+ optional language-model summaries may require manual review;
* automatic candidate-refinement synthesis is not yet part of the validated workflow;
* the HPC adapter is experimental and the local execution path is the primary tested configuration;
* internal APIs and artifact schemas may change before the first stable research release.

### Project context

ModalLens is developed as a research prototype within the LogiKEy and LoDEx environment. Its purpose is to make finite semantic structures inspectable and to support accountable, human-guided analysis of modal specifications.