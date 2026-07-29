#!/usr/bin/env bash
set -euo pipefail

THEORY="${1:-lib/data/Input.thy}"
OUTPUT="${2:-out/demo}"

mix escript.build
./axiom_refiner demo "$THEORY" -o "$OUTPUT"