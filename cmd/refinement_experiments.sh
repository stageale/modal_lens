#!/usr/bin/env bash
set -uo pipefail

PROFILE="${1:-mini}"
VERBALIZE_OPTION="${2:---no-verbalize}"

RUN_ID="${RUN_ID:-$(date '+%Y%m%d_%H%M%S')}"
MAX_REFINEMENT_ROUNDS="${MAX_REFINEMENT_ROUNDS:-1}"

usage() {
  echo "Usage: $0 mini|full [--verbalize|--no-verbalize]" >&2
}

case "$PROFILE" in
  mini)
    CARDINALITY="2-4"
    MAX_MODELS=6
    ;;
  full)
    CARDINALITY="${CARDINALITY:-2-5}"
    MAX_MODELS="${MAX_MODELS:-20}"
    ;;
  *)
    usage
    exit 2
    ;;
esac

case "$VERBALIZE_OPTION" in
  --verbalize)
    VERBALIZATION_LABEL="enabled"
    VERBALIZATION_ARGS=(
      --verbalize
      --verbalization-backend ollama
      --verbalization-model qwen3.5:9b
      --verbalization-mode grounded
      --verbalization-reasoning on
      --verbalization-max-new-tokens 8192
    )
    ;;
  --no-verbalize)
    VERBALIZATION_LABEL="disabled"
    VERBALIZATION_ARGS=(--no-verbalize)
    ;;
  *)
    usage
    exit 2
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUTPUT_ROOT="out/refinement_experiments/${PROFILE}_${RUN_ID}"
STATUS_FILE="$OUTPUT_ROOT/status.tsv"

mkdir -p "$OUTPUT_ROOT"
printf "experiment\tstatus\tapplied\tinitial_models\tfinal_models\tstop_reason\n" \
  > "$STATUS_FILE"

mix escript.build || exit 1

CASES=(
  "01_chisholm_sdl|input/Chisholm.thy|sdl|go,tell|-"
  "02_chisholm_ddl|input/Dyadic_Chisholm.thy|ddl|go,tell|-"
  "03_article20_ddl|input/AIAct_Article20_DDL.thy|ddl|conform,corrective_action|-"
  "04_article20_edstit|input/AIAct_Article20_EDSTIT.thy|ed_stit|conform,corrective_action|1"
  "05_article36_edstit|input/AIAct_Article36_EDSTIT.thy|ed_stit|meets_requirements,investigate,designation_suspended,inform_providers|2"
)

failures=0

for specification in "${CASES[@]}"; do
  IFS='|' read -r name theory logic atoms agent_cardinality <<< "$specification"

  out="$OUTPUT_ROOT/$name"
  report="$out/refinement.json"
  mkdir -p "$out"

  if [[ -f "$report" ]] &&
     [[ "$(jq -r '.applied_refinement_count // 0' "$report")" -ge 1 ]]
  then
    echo "Skipping completed experiment: $name"
    continue
  fi

  echo
  echo "========================================"
  echo "Running:       $name"
  echo "Profile:       $PROFILE"
  echo "Cardinality:   $CARDINALITY"
  echo "Max models:    $MAX_MODELS"
  echo "Output:        $out"
  echo "Verbalization: $VERBALIZATION_LABEL"
  echo "========================================"

  args=(
    refine "$theory"
    --model-logic "$logic"
    --atoms "$atoms"
    --no-auto-atoms
    --backend local
    --cardinality "$CARDINALITY"
    --max-models "$MAX_MODELS"
    --no-cardinality-feature
    --feature-method graphlet
    --graphlet-size 3
    --render-graph --graph-format svg --palette turbo
    "${VERBALIZATION_ARGS[@]}"
    --max-refinement-rounds "$MAX_REFINEMENT_ROUNDS"
    --auto-refine
    --out-dir "$out"
  )

  if [[ "$agent_cardinality" != "-" ]]; then
    args+=(--agent-cardinality "$agent_cardinality")
  fi

  if [[ "$logic" != "ed_stit" ]]; then
    args+=(--relation R)
  fi

  if ./modal_lens "${args[@]}" 2>&1 | tee "$out/console.log"; then
    command_status=0
  else
    command_status=$?
  fi

  if [[ "$command_status" -eq 0 && -f "$report" ]]; then
    applied="$(jq -r '.applied_refinement_count // 0' "$report")"
    initial="$(jq -r '.initial.enumeration.model_count // 0' "$report")"
    final="$(jq -r '.final.enumeration.model_count // 0' "$report")"
    reason="$(jq -r '.stop_reason // "unknown"' "$report")"

    if [[ "$applied" -ge 1 ]]; then
      status="OK"
    else
      status="NO_REFINEMENT"
      failures=$((failures + 1))
    fi
  else
    status="FAILED"
    applied=0
    initial=0
    final=0
    reason="command_failed"
    failures=$((failures + 1))
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$name" "$status" "$applied" "$initial" "$final" "$reason" \
    >> "$STATUS_FILE"
done

echo
echo "========================================"
echo "Summary"
echo "========================================"
column -t -s $'\t' "$STATUS_FILE" 2>/dev/null || cat "$STATUS_FILE"
echo
echo "Output root: $OUTPUT_ROOT"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
