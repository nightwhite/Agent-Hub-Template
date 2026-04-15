#!/usr/bin/env bash
set -euo pipefail

KIND="${1:-agents}"

python3 - "$KIND" <<'PY'
import json
import sys
from pathlib import Path

kind = sys.argv[1]
if kind not in {"agents", "bases"}:
    raise SystemExit(f"unsupported kind: {kind}")

file_map = {
    "agents": Path("registry/agents.yaml"),
    "bases": Path("registry/bases.yaml"),
}

lines = file_map[kind].read_text().splitlines()
items = []
current = None

for raw in lines:
    line = raw.rstrip()
    stripped = line.strip()
    if stripped.startswith(f"{kind}:"):
        continue
    if stripped.startswith("- name:"):
        if current:
            items.append(current)
        current = {"name": stripped.split(":", 1)[1].strip()}
        continue
    if not current:
        continue
    if ":" in stripped:
        key, value = stripped.split(":", 1)
        current[key.strip()] = value.strip()

if current:
    items.append(current)

enabled = [item for item in items if item.get("enabled", "true").lower() == "true"]

if kind == "agents":
    base_meta = {}
    for raw in Path("registry/bases.yaml").read_text().splitlines():
        stripped = raw.strip()
        if stripped.startswith("- name:"):
            name = stripped.split(":", 1)[1].strip()
            base_meta[name] = {"name": name}
        elif base_meta and ":" in stripped:
            key, value = stripped.split(":", 1)
            base_meta[name][key.strip()] = value.strip()

    for item in enabled:
        base_name = item.get("base", "ubuntu")
        item["base_image"] = base_meta.get(base_name, {}).get("image", f"agent-hub/base-{base_name}:dev")

print(json.dumps({"include": enabled}))
PY
