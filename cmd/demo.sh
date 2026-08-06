#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

SDL_THEORY="examples/input/Chisholm.thy"
DDL_THEORY="examples/input/Dyadic_Chisholm.thy"
OUTPUT_ROOT="out/demo"

usage() {
  cat <<'EOF'
Usage:
  ./cmd/demo.sh all
  ./cmd/demo.sh sdl <tikz|svg> [additional demo options]
  ./cmd/demo.sh ddl <tikz|svg> [additional demo options]

Arguments:
  sdl | ddl     Select the model logic.
  tikz | svg    Use TikZ or SVG as the displayed graph format.
  all           Run all four combinations.

Examples:
  ./cmd/demo.sh sdl svg
  ./cmd/demo.sh sdl tikz
  ./cmd/demo.sh ddl svg
  ./cmd/demo.sh ddl tikz
  ./cmd/demo.sh all

Additional options are forwarded to the demo command:

  ./cmd/demo.sh ddl tikz --verbalize
  ./cmd/demo.sh sdl svg --palette viridis
EOF
}

run_demo() {
  local model_logic="$1"
  local tikz_enabled="$2"
  shift 2

  local theory
  local graph_format
  local output_dir

  case "$model_logic" in
    sdl)
      theory="$SDL_THEORY"
      ;;
    ddl)
      theory="$DDL_THEORY"
      ;;
    *)
      echo "[ERROR] Unsupported model logic: $model_logic" >&2
      usage
      exit 2
      ;;
  esac

  case "$tikz_enabled" in
    tikz)
      graph_format="tikz"
      ;;
    svg)
      graph_format="svg"
      ;;
    *)
      echo "[ERROR] TikZ must be either 'tikz' or 'svg'." >&2
      usage
      exit 2
      ;;
  esac

  output_dir="${OUTPUT_ROOT}/${model_logic}_${graph_format}"

  echo
  echo "========================================"
  echo " Demo"
  echo "========================================"
  echo "Logic:        $model_logic"
  echo "Graph format: $graph_format"
  echo "Theory:       $theory"
  echo "Output:       $output_dir"
  echo

  ./modal_lens demo "$theory" \
    --model-logic "$model_logic" \
    --graph-format "$graph_format" \
    --palette turbo \
    --out-dir "$output_dir" \
    "$@"
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 2
  fi

  mix escript.build

  case "$1" in
    all)
      shift

      run_demo sdl svg "$@"
      run_demo sdl tikz "$@"
      run_demo ddl svg "$@"
      run_demo ddl tikz "$@"
      ;;

    sdl | ddl)
      if [[ $# -lt 2 ]]; then
        echo "[ERROR] Missing TikZ selection." >&2
        usage
        exit 2
      fi

      run_demo "$@"
      ;;

    help | --help | -h)
      usage
      ;;

    *)
      echo "[ERROR] Unknown demo selection: $1" >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"