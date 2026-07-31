#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo
echo "========================================"
echo " Elixir tests"
echo "========================================"

MIX_ENV=test mix test --trace

echo
echo "========================================"
echo " Python tests"
echo "========================================"

uv run --locked python -m pytest -v

echo
echo "========================================"
echo " All tests passed"
echo "========================================"

