#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_ID="${RUN_ID:-$(date '+%Y%m%d_%H%M%S')}"
OUTPUT_ROOT="out/paper_experiments/$RUN_ID"

mkdir -p "$OUTPUT_ROOT"

mix escript.build

run_experiment() {
  local name="$1"
  local theory="$2"
  local logic="$3"
  local atoms="$4"

  local output="$OUTPUT_ROOT/$name"
  if [[ -f "$output/refinement.json" ]]; then
    echo "Skipping completed experiment: $name"
    return
  fi
  mkdir -p "$output"

  local args=(
    refine "$theory"
    --model-logic "$logic"
    --atoms "$atoms"
    --no-auto-atoms
    --backend local
    --cardinality 2-5
    --max-models 20
    --no-cardinality-feature
    --render-graph
    --graph-format svg
    --palette turbo
    --verbalize
    --verbalization-backend ollama
    --verbalization-model qwen3.5:9b
    --verbalization-mode grounded
    --verbalization-reasoning on
    --verbalization-max-new-tokens 8192
    --max-refinement-rounds 1
    --auto-refine
    --out-dir "$output"
  )

  if [[ "$logic" != "ed_stit" ]]; then
    args+=(--relation R)
  fi

  echo
  echo "========================================"
  echo "Running: $name"
  echo "Output:  $output"
  echo "========================================"

  ./modal_lens "${args[@]}" 2>&1 |
    tee "$output/console.log"

  if [[ ! -f "$output/refinement.json" ]]; then
    echo "[ERROR] No refinement.json produced for $name" >&2
    exit 1
  fi
}

run_experiment \
  "01_chisholm_sdl" \
  "input/Chisholm.thy" \
  "sdl" \
  "go,tell"

run_experiment \
  "02_chisholm_ddl" \
  "input/Dyadic_Chisholm.thy" \
  "ddl" \
  "go,tell"

run_experiment \
  "03_article20_ddl" \
  "input/AIAct_Article20_DDL.thy" \
  "ddl" \
  "conform,corrective_action"

run_experiment \
  "04_article20_edstit" \
  "input/AIAct_Article20_EDSTIT.thy" \
  "ed_stit" \
  "conform,corrective_action"

run_experiment \
  "05_article36_edstit" \
  "input/AIAct_Article36_EDSTIT.thy" \
  "ed_stit" \
  "meets_requirements,investigate"

echo
echo "All experiments completed."
echo "Results: $OUTPUT_ROOT"