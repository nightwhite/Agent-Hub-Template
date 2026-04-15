#!/usr/bin/env bash
set -euo pipefail

AGENT="${1:-hermes}"
META_FILE="agents/${AGENT}/agent.yaml"
TEST_SCRIPT="agents/${AGENT}/tests/smoke.sh"

if [[ ! -x "$TEST_SCRIPT" ]]; then
  echo "Test script missing or not executable: $TEST_SCRIPT" >&2
  exit 1
fi

META_REPOSITORY="$(awk '/repository:/{print $2; exit}' "$META_FILE")"
REPOSITORY="${AGENT_REGISTRY_OVERRIDE:-${REGISTRY_OVERRIDE:-$META_REPOSITORY}}"
IMAGE="${REPOSITORY}:${AGENT_TAG:-dev}"

"$TEST_SCRIPT" "$IMAGE"
