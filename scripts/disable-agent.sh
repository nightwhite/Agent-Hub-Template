#!/usr/bin/env bash
set -euo pipefail

AGENT="${1:-}"
if [[ -z "$AGENT" ]]; then
  echo "Usage: $0 <agent-name>" >&2
  exit 1
fi

python3 scripts/repo_meta.py set-enabled agents "$AGENT" disabled >/dev/null
printf 'Disabled agent: %s\n' "$AGENT"
