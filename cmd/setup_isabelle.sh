#!/usr/bin/env bash
set -euo pipefail

ISABELLE_BIN="${MODAL_LENS_ISABELLE_BIN:-}"

if [[ -z "$ISABELLE_BIN" ]]; then
  if ! ISABELLE_BIN="$(command -v isabelle)"; then
    echo "[ERROR] Isabelle was not found in PATH." >&2
    echo "Set MODAL_LENS_ISABELLE_BIN to the Isabelle executable." >&2
    exit 1
  fi
fi

if [[ ! -x "$ISABELLE_BIN" ]]; then
  echo "[ERROR] Isabelle executable is not valid: $ISABELLE_BIN" >&2
  exit 1
fi

echo "Using Isabelle: $ISABELLE_BIN"
echo "Preparing the Isabelle/HOL user heap..."

"$ISABELLE_BIN" build \
  -b \
  -j 1 \
  -o system_heaps=false \
  -o threads=2 \
  HOL

echo "Isabelle/HOL heap is ready."