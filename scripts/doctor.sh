#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Agent Hub doctor"
echo

echo "[1/4] Registry and metadata validation"
./scripts/validate-registry.sh

echo
echo "[2/4] Registered agent status"
./scripts/status-agents.sh

echo
echo "[3/4] Shell script syntax"
bash -n scripts/*.sh

echo
echo "[4/4] Python helper syntax"
python3 -m py_compile scripts/repo_meta.py

if [[ -d scripts/__pycache__ ]]; then
  rm -rf scripts/__pycache__
fi

echo
echo "Doctor check passed."
