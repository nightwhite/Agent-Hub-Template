#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY' | while read -r base; do
from pathlib import Path
import re

items = []
current = None
for raw in Path('registry/bases.yaml').read_text().splitlines():
    line = raw.strip()
    if line.startswith('- name:'):
        current = {'name': line.split(':', 1)[1].strip(), 'enabled': True}
    elif current and line.startswith('enabled:'):
        current['enabled'] = line.split(':', 1)[1].strip().lower() == 'true'
        items.append(current)
        current = None
for item in items:
    if item.get('enabled', True):
        print(item['name'])
PY
  ./scripts/build-base.sh "$base"
done

python3 - <<'PY' | while read -r agent; do
from pathlib import Path

items = []
current = None
for raw in Path('registry/agents.yaml').read_text().splitlines():
    line = raw.strip()
    if line.startswith('- name:'):
        current = {'name': line.split(':', 1)[1].strip(), 'enabled': True}
    elif current and line.startswith('enabled:'):
        current['enabled'] = line.split(':', 1)[1].strip().lower() == 'true'
        items.append(current)
        current = None
for item in items:
    if item.get('enabled', True):
        print(item['name'])
PY
  ./scripts/build-agent.sh "$agent"
done
