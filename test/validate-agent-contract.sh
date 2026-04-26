#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -gt 0 ]]; then
  agents=("$@")
else
  agents=(agents/_template agents/hermes agents/openclaw)
fi
required_files=(Dockerfile install.sh entrypoint.sh config.sh config.json index.json deploy.yaml README.md)

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

validate_json_file() {
  local file="$1"
  python3 -m json.tool "$file" >/dev/null
}

validate_yaml_file() {
  local file="$1"
  command -v ruby >/dev/null 2>&1 || fail "ruby is required to validate YAML: $file"
  ruby -e 'require "yaml"; YAML.load_file(ARGV[0])' "$file" >/dev/null
}

validate_manifest() {
  local agent_dir="$1"
  python3 - "$agent_dir/config.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
if data.get("schemaVersion") != "devbox-agent-config.v1":
    raise SystemExit(f"{path}: missing schemaVersion devbox-agent-config.v1")
if data.get("script") != "/opt/agent/config.sh":
    raise SystemExit(f"{path}: script must be /opt/agent/config.sh")
allowed_kinds = {"read", "write", "delete"}
allowed_types = {"text", "password", "number", "select"}
for locale in ("zh", "en"):
    resources = data.get(locale, {}).get("resources")
    if not isinstance(resources, list) or not resources:
        raise SystemExit(f"{path}: {locale}.resources must be a non-empty list")
    for resource in resources:
        if not resource.get("resource"):
            raise SystemExit(f"{path}: resource id is required")
        actions = resource.get("actions")
        if not isinstance(actions, list) or not actions:
            raise SystemExit(f"{path}: resource {resource.get('resource')} needs actions")
        for action in actions:
            kind = action.get("kind")
            if kind not in allowed_kinds:
                raise SystemExit(f"{path}: action {action.get('action')} has invalid kind {kind!r}")
            args = action.get("args")
            if not isinstance(args, list):
                raise SystemExit(f"{path}: action {action.get('action')} args must be a list")
            for arg in args:
                arg_type = arg.get("type")
                if arg_type not in allowed_types:
                    raise SystemExit(f"{path}: arg {arg.get('name')} has invalid type {arg_type!r}")
                if arg_type == "password" and arg.get("sensitive") is not True:
                    raise SystemExit(f"{path}: password arg {arg.get('name')} must set sensitive=true")
PY
}

validate_index() {
  local agent_dir="$1"
  python3 - "$agent_dir/index.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
kind = data.get("runtime", {}).get("kind")
if kind not in {"service", "tool"}:
    raise SystemExit(f"{path}: runtime.kind must be service or tool")
PY
}

for agent_dir in "${agents[@]}"; do
  [[ -d "$agent_dir" ]] || fail "agent directory not found: $agent_dir"
  printf '==> validating %s\n' "$agent_dir"

  for required in "${required_files[@]}"; do
    [[ -f "$agent_dir/$required" ]] || fail "$agent_dir is missing $required"
  done

  bash -n "$agent_dir/install.sh"
  bash -n "$agent_dir/entrypoint.sh"
  bash -n "$agent_dir/config.sh"
  validate_json_file "$agent_dir/config.json"
  validate_json_file "$agent_dir/index.json"
  validate_yaml_file "$agent_dir/deploy.yaml"
  validate_manifest "$agent_dir"
  validate_index "$agent_dir"

  grep -F 'ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]' "$agent_dir/Dockerfile" >/dev/null || \
    fail "$agent_dir/Dockerfile must keep the /init entrypoint"
  grep -F 'CMD ["start"]' "$agent_dir/Dockerfile" >/dev/null || \
    fail "$agent_dir/Dockerfile must default CMD to start"
  grep -F 'config.json /opt/agent/config.json' "$agent_dir/Dockerfile" >/dev/null || \
    fail "$agent_dir/Dockerfile must copy config.json to /opt/agent/config.json"
  grep -F 'args: ["start"]' "$agent_dir/deploy.yaml" >/dev/null || \
    fail "$agent_dir/deploy.yaml must keep args: [\"start\"]"
  grep -F 'json_success' "$agent_dir/config.sh" >/dev/null || \
    fail "$agent_dir/config.sh must emit JSON success envelopes"
  grep -F 'json_error' "$agent_dir/config.sh" >/dev/null || \
    fail "$agent_dir/config.sh must emit JSON error envelopes"
done

printf '==> agent contract validation passed\n'
