# Command-line interface

## Status

The `demo` command is the primary reviewer-facing workflow. `enumerate` exposes the lower-level finite-model search. `summary` and `axiom` are utilities for already stored Nitpick output.

Commands in this document use the intended executable name:

```text
./modal_lens
```

Until the mechanical rename is complete, the current binary may still be `./axiom_refiner`.

## Build

```bash
mix escript.build
```

## `demo`

Runs the canonical pipeline and writes the HTML review interface.

```bash
./modal_lens demo INPUT.thy [options]
```

Example:

```bash
./modal_lens demo examples/input/Chisholm.thy \
  -o out/demo \
  --model-logic sdl \
  --max-models 5 \
  --graph-format svg \
  --palette turbo \
  --no-verbalize
```

Important options:

| Option | Meaning | Default |
|---|---|---|
| `-o`, `--out-dir DIR` | Output directory | `out/demo` |
| `--model-logic LOGIC` | `sdl` or `ddl` | `sdl` |
| `--relation NAME` | Nitpick relation name | `R` |
| `--atoms a,b,c` | Explicit atom names | empty |
| `--no-auto-atoms` | Disable additional unary-predicate detection | detection enabled |
| `--max-models N` | Maximum discovered models | `10` |
| `--no-render-graph` | Suppress DOT, SVG, TikZ, and PDF files | rendering enabled |
| `--graph-format FORMAT` | Preferred UI/rendering format, `svg` or `tikz` | `svg` |
| `--palette NAME` | Highlight palette | `turbo` |
| `--no-verbalize` | Disable cluster verbalisation | enabled |
| `--verbalization-model ID` | Backend model identifier | configured default |

Boolean options use direct polarity:

```text
--verbalize     → true
--no-verbalize  → false
```

An absent option uses the canonical default from `Execution.Options`.

## `enumerate`

Runs model enumeration without graph analysis or the HTML interface.

```bash
./modal_lens enumerate \
  --input INPUT.thy \
  --mode MODE \
  [options]
```

Valid modes:

| CLI value | Internal mode | Semantics |
|---|---|---|
| `countermodels` | `:countermodels` | Search for finite countermodels to `axiom_refiner_query` |
| `satisfying-models` | `:satisfying_models` | Search for finite models satisfying the base theory |
| `consistency-check` | `:consistency_check` | Search for at most one finite model |

Example:

```bash
./modal_lens enumerate \
  --input examples/input/Chisholm.thy \
  --mode countermodels \
  --model-logic sdl \
  --max-models 5 \
  --out-dir out/enumeration/chisholm
```

Additional options include:

| Option | Meaning |
|---|---|
| `--search-theory-dir DIR` | Directory for generated search theories |
| `--isabelle-bin PATH` | Isabelle executable |
| `--threads N` | Isabelle thread count |
| `--include-atoms` / `--no-include-atoms` | Include valuations in blocking axioms |
| `--include-designated-world` / `--no-include-designated-world` | Include the designated world in blocking axioms |

### Countermodel mode

The base theory must define the query expected by the generated probe:

```isabelle
abbreviation axiom_refiner_query :: bool where
  "axiom_refiner_query \<equiv> ..."
```

The generated theory asks Nitpick for a counterexample and accumulates blocking axioms.

### Satisfying-model mode

The generated theory uses a trivial proposition with Nitpick's satisfying-model mode. Every discovered finite model is blocked before the next iteration.

### Consistency-check mode

The search stops after the first discovered finite model. Failure to find one within the finite scope is not a general proof of inconsistency.

## `summary`

Parses stored Nitpick output and prints a compact model summary.

```bash
./modal_lens summary OUTPUT.txt \
  --model-logic sdl \
  --atoms go,tell
```

Use `--json` for machine-readable output. Automatic atom detection is enabled unless `--no-auto-atoms` is passed.

## `axiom`

Parses stored Nitpick output and emits an Isabelle blocking-axiom fragment.

```bash
./modal_lens axiom OUTPUT.txt \
  --model-logic sdl \
  -o out/axioms
```

Relevant options:

- `--no-atoms`: omit valuations from the finite-structure description;
- `--include-designated-world`: include the logic-specific designated world;
- `--designated-world-constant NAME`: override the generated constant name.

## Exit behaviour

The CLI uses non-zero exit codes for:

- invalid options;
- missing required inputs;
- unknown commands or modes;
- failed enumeration;
- failed demo execution.

Detailed execution failures are printed as structured Elixir terms so that the failing boundary remains visible during prototype development.
