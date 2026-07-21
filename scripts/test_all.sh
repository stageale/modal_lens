#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

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

