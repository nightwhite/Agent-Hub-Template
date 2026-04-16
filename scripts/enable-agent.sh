#!/usr/bin/env bash
set -euo pipefail

AGENT="${1:-}"
if [[ -z "$AGENT" ]]; then
  echo "Usage: $0 <agent-name>" >&2
  exit 1
fi

python3 scripts/repo_meta.py set-enabled agents "$AGENT" enabled >/dev/null
printf 'Enabled agent: %s\n' "$AGENT"
