#!/usr/bin/env bash
set -euo pipefail

AGENT="${1:-}"

if [[ -z "$AGENT" ]]; then
  echo "Usage: $0 <agent-name>" >&2
  exit 1
fi

TARGET="agents/${AGENT}"
if [[ -e "$TARGET" ]]; then
  echo "Target already exists: $TARGET" >&2
  exit 1
fi

cp -R agents/_template "$TARGET"

AGENT_NAME="$AGENT" TARGET_DIR="$TARGET" python3 - <<'PY'
import os
from pathlib import Path

agent = os.environ['AGENT_NAME']
target = Path(os.environ['TARGET_DIR'])
for path in target.rglob('*'):
    if path.is_file():
        text = path.read_text()
        text = text.replace('change-me', agent)
        path.write_text(text)
PY

cat >> registry/agents.yaml <<EOF
  - name: ${AGENT}
    path: agents/${AGENT}
    base: ubuntu
    image: agent-hub/${AGENT}:dev
    enabled: false
EOF

echo "Created new agent scaffold at $TARGET and appended registry/agents.yaml"
