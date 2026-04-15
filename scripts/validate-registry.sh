#!/usr/bin/env bash
set -euo pipefail

for file in registry/bases.yaml registry/agents.yaml; do
  [[ -f "$file" ]] || { echo "Missing registry file: $file" >&2; exit 1; }
done

python3 - <<'PY'
from pathlib import Path
import sys

errors = []

for registry_file, kind in [('registry/bases.yaml', 'base'), ('registry/agents.yaml', 'agent')]:
    current = {}
    for raw in Path(registry_file).read_text().splitlines():
        line = raw.strip()
        if line.startswith('- name:'):
            current = {'name': line.split(':', 1)[1].strip()}
        elif current and line.startswith('path:'):
            current['path'] = line.split(':', 1)[1].strip()
        elif current and line.startswith('enabled:'):
            current['enabled'] = line.split(':', 1)[1].strip().lower() == 'true'
            if current.get('enabled', True):
                path = Path(current['path'])
                if not path.exists():
                    errors.append(f"Missing {kind} path: {path}")
                elif kind == 'base' and not (path / 'Dockerfile').exists():
                    errors.append(f"Missing base Dockerfile in {path}")
                elif kind == 'agent' and not (path / 'Dockerfile').exists():
                    errors.append(f"Missing agent Dockerfile in {path}")
            current = {}

required_dirs = ['agents/_template', 'shared/scripts', 'scripts']
for item in required_dirs:
    if not Path(item).exists():
        errors.append(f"Missing required directory: {item}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)

print('Registry and expected directories look valid.')
PY
