#!/usr/bin/env bash
set -euo pipefail

ISABELLE_BIN="$(command -v isabelle)"

if [[ -z "$ISABELLE_BIN" ]]; then
  echo "ERROR: Isabelle was not found in PATH." >&2
  exit 1
fi

export AXIOM_REFINER_ISABELLE_BIN="$ISABELLE_BIN"

echo "Loaded axiom_refiner environment"
echo "AXIOM_REFINER_ISABELLE_BIN=$AXIOM_REFINER_ISABELLE_BIN"

BASHRC="$HOME/.bashrc"
EXPORT_LINE="export AXIOM_REFINER_ISABELLE_BIN=\"$ISABELLE_BIN\""

if ! grep -Fqx "$EXPORT_LINE" "$BASHRC" 2>/dev/null; then
  {
    echo ""
    echo "# axiom_refiner Isabelle configuration"
    echo "$EXPORT_LINE"
  } >> "$BASHRC"

  echo "Added Isabelle configuration to $BASHRC"
else
  echo "Isabelle configuration already exists in $BASHRC"
fi

echo "Preparing Isabelle/HOL user heap..."

"$ISABELLE_BIN" build \
  -b \
  -j 1 \
  -o system_heaps=false \
  -o threads=2 \
  HOL

echo "Isabelle/HOL heap is ready."
echo "Future terminal sessions will load the Isabelle path automatically."