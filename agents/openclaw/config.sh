#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-openclaw}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/agent/.openclaw}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
OPENCLAW_DOTENV_FILE="${OPENCLAW_DOTENV_FILE:-${OPENCLAW_STATE_DIR}/.env}"
OPENCLAW_MAIN_AGENT_DIR="${OPENCLAW_MAIN_AGENT_DIR:-${OPENCLAW_STATE_DIR}/agents/main/agent}"
OPENCLAW_AUTH_PROFILES_FILE="${OPENCLAW_AUTH_PROFILES_FILE:-${OPENCLAW_MAIN_AGENT_DIR}/auth-profiles.json}"
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-/workspace}"
PATH="/usr/local/bin:${PATH}"
CURRENT_RESOURCE=""
CURRENT_ACTION=""

json_quote() {
  node -e 'process.stdout.write(JSON.stringify(process.argv[1] ?? ""))' "${1-}"
}

json_success() {
  local resource="${1:-$CURRENT_RESOURCE}"
  local action="${2:-$CURRENT_ACTION}"
  local applied="${3:-true}"
  local data="${4:-}"

  [[ -n "$data" ]] || data='{}'
  printf '{"ok":true,"resource":%s,"action":%s,"applied":%s,"data":%s}\n' \
    "$(json_quote "$resource")" \
    "$(json_quote "$action")" \
    "$applied" \
    "$data"
}

json_error() {
  local resource="${1:-$CURRENT_RESOURCE}"
  local action="${2:-$CURRENT_ACTION}"
  local code="${3:-error}"
  local message="${4:-unknown error}"

  printf '{"ok":false,"resource":%s,"action":%s,"error":{"code":%s,"message":%s}}\n' \
    "$(json_quote "$resource")" \
    "$(json_quote "$action")" \
    "$(json_quote "$code")" \
    "$(json_quote "$message")"
}

fail() {
  local message="$*"
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$message" >&2
  json_error "$CURRENT_RESOURCE" "$CURRENT_ACTION" "invalid_config" "$message"
  exit 1
}

require_arg() {
  local value="${1-}"
  local name="${2:-argument}"
  [[ -n "$value" ]] || fail "missing ${name}"
}

run_as_agent_script() {
  if [[ "$(id -u)" -eq 0 ]] && [[ "${OPENCLAW_CONFIG_AS_AGENT:-1}" == "1" ]]; then
    exec runuser -u agent -- env \
      OPENCLAW_CONFIG_AS_AGENT=0 \
      AGENT_NAME="$AGENT_NAME" \
      OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
      OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
      OPENCLAW_DOTENV_FILE="$OPENCLAW_DOTENV_FILE" \
      OPENCLAW_MAIN_AGENT_DIR="$OPENCLAW_MAIN_AGENT_DIR" \
      OPENCLAW_AUTH_PROFILES_FILE="$OPENCLAW_AUTH_PROFILES_FILE" \
      OPENCLAW_WORKSPACE="$OPENCLAW_WORKSPACE" \
      HOME=/home/agent \
      PATH="$PATH" \
      /opt/agent/config.sh "$@"
  fi
}

ensure_openclaw_state() {
  mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE"

  if [[ ! -f "$OPENCLAW_CONFIG_PATH" ]]; then
    cat >"$OPENCLAW_CONFIG_PATH" <<EOF_JSON
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "${OPENCLAW_WORKSPACE}",
      "model": {
        "primary": "openai/gpt-5.4"
      }
    }
  }
}
EOF_JSON
  fi

  if [[ ! -f "$OPENCLAW_DOTENV_FILE" ]]; then
    cat >"$OPENCLAW_DOTENV_FILE" <<'EOF_ENV'
OPENCLAW_GATEWAY_TOKEN=change-me-local-dev
EOF_ENV
  fi
}

openclaw_cli() {
  HOME=/home/agent \
  OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
  OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
  PATH="$PATH" \
  openclaw "$@"
}

dotenv_set() {
  local key="${1:?missing key}"
  local value="${2:-}"
  local temp_file
  local found=0

  ensure_openclaw_state
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${key}="* ]]; then
      printf '%s=%s\n' "$key" "$value" >>"$temp_file"
      found=1
    else
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$OPENCLAW_DOTENV_FILE"

  if [[ "$found" -eq 0 ]]; then
    printf '%s=%s\n' "$key" "$value" >>"$temp_file"
  fi

  mv "$temp_file" "$OPENCLAW_DOTENV_FILE"
}

dotenv_delete() {
  local key="${1:?missing key}"
  local temp_file

  ensure_openclaw_state
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" != "${key}="* ]]; then
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$OPENCLAW_DOTENV_FILE"

  mv "$temp_file" "$OPENCLAW_DOTENV_FILE"
}

dotenv_json() {
  node - "$OPENCLAW_DOTENV_FILE" "$@" <<'NODE'
const fs = require('fs');
const [file, command, key] = process.argv.slice(2);
const values = {};
if (fs.existsSync(file)) {
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    const idx = line.indexOf('=');
    values[line.slice(0, idx)] = line.slice(idx + 1);
  }
}
const status = (currentKey) => {
  const value = values[currentKey];
  const configured = Boolean(value);
  return { key: currentKey, configured, masked: configured ? '********' : null };
};
if (command === 'get') {
  process.stdout.write(JSON.stringify(status(key)));
} else if (command === 'list') {
  process.stdout.write(JSON.stringify({ values: Object.fromEntries(Object.entries(values).map(([k]) => [k, status(k)])) }));
} else {
  throw new Error(`unknown dotenv command: ${command}`);
}
NODE
}

auth_profile_json() {
  node - "$OPENCLAW_AUTH_PROFILES_FILE" "$@" <<'NODE'
const fs = require('fs');
const path = require('path');

const [file, command, provider, secretValue, profileArg] = process.argv.slice(2);
const profileId = profileArg || `${provider}:default`;

const emptyStore = () => ({ version: 1, profiles: {} });
const readStore = () => {
  if (!fs.existsSync(file)) return emptyStore();
  const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!parsed || typeof parsed !== 'object') return emptyStore();
  if (!parsed.profiles || typeof parsed.profiles !== 'object') parsed.profiles = {};
  if (!Number.isFinite(Number(parsed.version))) parsed.version = 1;
  return parsed;
};
const writeStore = (store) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(store, null, 2)}\n`);
};
const status = (store) => {
  const profile = store.profiles[profileId];
  const configured = Boolean(profile && profile.type === 'api_key' && profile.provider === provider && profile.key);
  return {
    provider,
    profile: profileId,
    configured,
    masked: configured ? '********' : null,
  };
};

if (!provider) {
  throw new Error('missing provider');
}

const store = readStore();
if (command === 'set-api-key') {
  if (!secretValue) throw new Error('missing api key');
  store.profiles[profileId] = {
    type: 'api_key',
    provider,
    key: secretValue,
  };
  writeStore(store);
  process.stdout.write(JSON.stringify(status(store)));
} else if (command === 'get-api-key') {
  process.stdout.write(JSON.stringify(status(store)));
} else if (command === 'delete-api-key') {
  delete store.profiles[profileId];
  writeStore(store);
  process.stdout.write(JSON.stringify(status(store)));
} else {
  throw new Error(`unknown auth profile command: ${command}`);
}
NODE
}

with_secrets_reload_status() {
  local auth_data="$1"
  local gateway_ready=0
  local reload_attempts="${OPENCLAW_SECRETS_RELOAD_RETRIES:-5}"
  local reload_data
  local reload_error
  local reload_error_file

  if wait_for_gateway_ready; then
    gateway_ready=1
  fi

  if [[ "$gateway_ready" -ne 1 ]]; then
    node - "$auth_data" <<'NODE'
const auth = JSON.parse(process.argv[2]);
process.stdout.write(JSON.stringify({
  auth,
  runtimeReload: {
    applied: false,
    skipped: true,
    reason: 'gateway_unavailable',
  },
}));
NODE
    return 0
  fi

  reload_error_file="$(mktemp)"
  for attempt in $(seq 1 "$reload_attempts"); do
    if reload_data="$(openclaw_cli secrets reload --json 2>"$reload_error_file")"; then
      break
    fi

    reload_error="$(cat "$reload_error_file")"
    : >"$reload_error_file"
    if [[ "$attempt" -eq "$reload_attempts" ]]; then
      rm -f "$reload_error_file" >/dev/null 2>&1 || true
      printf '%s\n' "$reload_error" >&2
      return 1
    fi
    printf '[%s] [INFO] secrets reload attempt %s/%s failed; retrying\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" "$reload_attempts" >&2
    sleep 5
  done
  rm -f "$reload_error_file" >/dev/null 2>&1 || true

  node - "$auth_data" "$reload_data" <<'NODE'
const auth = JSON.parse(process.argv[2]);
const rawReload = process.argv[3] || '{}';
let reload;
try {
  reload = JSON.parse(rawReload);
} catch {
  reload = { raw: rawReload };
}
process.stdout.write(JSON.stringify({
  auth,
  runtimeReload: {
    applied: true,
    skipped: false,
    data: reload,
  },
}));
NODE
}

auth_profile_json_with_reload() {
  local auth_data

  if ! auth_data="$(auth_profile_json "$@")"; then
    return 1
  fi

  with_secrets_reload_status "$auth_data"
}

build_provider_payload() {
  local current_json="${1:-}"
  local base_url="${2:-}"
  local api_mode="${3:-}"
  node - "$current_json" "$base_url" "$api_mode" <<'NODE'
const [currentJson, baseUrl, apiMode] = process.argv.slice(2);
const payload = currentJson ? JSON.parse(currentJson) : {};
if (!Array.isArray(payload.models)) payload.models = [];
if (baseUrl) payload.baseUrl = baseUrl;
if (apiMode) payload.api = apiMode;
process.stdout.write(JSON.stringify(payload));
NODE
}

wait_for_gateway_ready() {
  local wait_seconds="${OPENCLAW_RUNTIME_APPLY_WAIT_SECONDS:-30}"
  local timeout_ms="${OPENCLAW_GATEWAY_HEALTH_TIMEOUT_MS:-3000}"

  for _ in $(seq 1 "$((wait_seconds + 1))"); do
    if openclaw_cli gateway health --json --timeout "$timeout_ms" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

gateway_call_json() {
  local method="${1:?missing gateway method}"
  local params="${2:-}"
  [[ -n "$params" ]] || params='{}'
  openclaw_cli gateway call "$method" \
    --params "$params" \
    --json \
    --timeout "${OPENCLAW_GATEWAY_CALL_TIMEOUT_MS:-30000}"
}

gateway_config_patch_json() {
  local raw_patch="${1:?missing config patch}"
  local snapshot
  local params

  snapshot="$(gateway_call_json config.get '{}')" || return 1
  params="$(node - "$raw_patch" "$snapshot" <<'NODE'
const [rawPatch, snapshotRaw] = process.argv.slice(2);
const snapshot = JSON.parse(snapshotRaw);
const baseHash = snapshot.hash || snapshot.configHash || snapshot.persistedHash;
if (!baseHash) {
  throw new Error('config.get did not return a base hash');
}
process.stdout.write(JSON.stringify({
  raw: rawPatch,
  baseHash,
  restartDelayMs: 0,
  note: 'Devbox adapter config update',
}));
NODE
)" || return 1

  gateway_call_json config.patch "$params"
}

build_model_patch() {
  local provider="${1:?missing provider}"
  local model="${2:?missing model}"
  node - "$provider" "$model" <<'NODE'
const [provider, model] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  agents: {
    defaults: {
      model: {
        primary: `${provider}/${model}`,
      },
    },
  },
}));
NODE
}

build_provider_patch() {
  local provider="${1:?missing provider}"
  local payload="${2:?missing provider payload}"
  node - "$provider" "$payload" <<'NODE'
const [provider, payloadRaw] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  models: {
    providers: {
      [provider]: JSON.parse(payloadRaw),
    },
  },
}));
NODE
}

build_provider_delete_patch() {
  local provider="${1:?missing provider}"
  node - "$provider" <<'NODE'
const [provider] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  models: {
    providers: {
      [provider]: null,
    },
  },
}));
NODE
}

build_workspace_patch() {
  local workspace="${1:?missing workspace}"
  node - "$workspace" <<'NODE'
const [workspace] = process.argv.slice(2);
process.stdout.write(JSON.stringify({
  agents: {
    defaults: {
      workspace,
    },
  },
}));
NODE
}

gateway_local_is_runtime_noop() {
  local current_json="${1:-}"
  local bind="${2:?missing bind}"
  local port="${3:?missing port}"
  [[ -n "$current_json" ]] || current_json='{}'
  node - "$current_json" "$bind" "$port" <<'NODE'
const [currentRaw, desiredBind, desiredPortRaw] = process.argv.slice(2);
const current = currentRaw ? JSON.parse(currentRaw) : {};
const currentMode = current.mode ?? 'local';
const currentBind = current.bind ?? 'lan';
const currentPort = current.port ?? 18789;
const desiredPort = Number(desiredPortRaw);
if (!Number.isInteger(desiredPort) || desiredPort <= 0) {
  process.exit(2);
}
process.exit(currentMode === 'local' && currentBind === desiredBind && Number(currentPort) === desiredPort ? 0 : 1);
NODE
}

combine_data_with_runtime_patch() {
  local data="${1:-}"
  local patch_result="${2:-}"
  [[ -n "$data" ]] || data='{}'
  [[ -n "$patch_result" ]] || patch_result='{}'
  node - "$data" "$patch_result" <<'NODE'
const [dataRaw, patchRaw] = process.argv.slice(2);
const parsedData = dataRaw ? JSON.parse(dataRaw) : {};
const patch = patchRaw ? JSON.parse(patchRaw) : {};
const restart = patch && typeof patch === 'object' ? patch.restart : undefined;
const restartRequired = Boolean(restart);
const applied = !restartRequired;
const runtimeApply = {
  applied,
  skipped: false,
  method: 'gateway.config.patch',
  restartRequired,
  noop: Boolean(patch.noop),
  path: patch.path ?? null,
};
if (restartRequired) {
  runtimeApply.restart = {
    coalesced: Boolean(restart.coalesced),
    delayMs: restart.delayMs ?? null,
  };
}
const data = parsedData && typeof parsedData === 'object' && !Array.isArray(parsedData)
  ? { ...parsedData, runtimeApply }
  : { value: parsedData, runtimeApply };
process.stdout.write(`${applied}\t${JSON.stringify(data)}`);
NODE
}

combine_data_with_runtime_skipped() {
  local data="${1:-}"
  local reason="${2:-gateway_unavailable}"
  [[ -n "$data" ]] || data='{}'
  node - "$data" "$reason" <<'NODE'
const [dataRaw, reason] = process.argv.slice(2);
const parsedData = dataRaw ? JSON.parse(dataRaw) : {};
const runtimeApply = {
  applied: false,
  skipped: true,
  reason,
};
const data = parsedData && typeof parsedData === 'object' && !Array.isArray(parsedData)
  ? { ...parsedData, runtimeApply }
  : { value: parsedData, runtimeApply };
process.stdout.write(`false\t${JSON.stringify(data)}`);
NODE
}

emit_runtime_success() {
  local resource="$1"
  local action="$2"
  local combined="$3"
  local applied
  local data

  applied="${combined%%$'\t'*}"
  data="${combined#*$'\t'}"
  json_success "$resource" "$action" "$applied" "$data"
}

emit_success_from_runtime_reload() {
  local resource="$1"
  local action="$2"
  shift 2
  local data
  local applied

  if ! data="$($@)"; then
    fail "failed to apply ${resource} ${action}"
  fi

  applied="$(node - "$data" <<'NODE'
const data = JSON.parse(process.argv[2] || '{}');
process.stdout.write(data?.runtimeReload?.applied === true ? 'true' : 'false');
NODE
)"
  json_success "$resource" "$action" "$applied" "$data"
}

usage() {
  json_error "" "" "usage" "usage: config.sh <resource> <action> [args...]"
  exit 1
}

emit_success_from() {
  local resource="$1"
  local action="$2"
  shift 2
  local data

  if ! data="$($@)"; then
    fail "failed to apply ${resource} ${action}"
  fi

  json_success "$resource" "$action" true "$data"
}

run_or_fail() {
  local message="$1"
  shift

  if ! "$@" >/dev/null; then
    fail "$message"
  fi
}

dispatch_config() {
  local resource="${1:?missing resource}"
  local action="${2:?missing action}"
  shift 2 || true

  case "${resource}:${action}" in
    model:set-main)
      require_arg "${1-}" "provider"
      require_arg "${2-}" "model"
      local patch_result
      local data
      if wait_for_gateway_ready; then
        patch_result="$(gateway_config_patch_json "$(build_model_patch "$1" "$2")")" || fail "failed to apply main model to running gateway"
        data="$(openclaw_cli config get agents.defaults.model --json)" || fail "failed to read main model"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" "$patch_result")"
      else
        run_or_fail "failed to set main model" openclaw_cli config set agents.defaults.model.primary "$1/$2"
        data="$(openclaw_cli config get agents.defaults.model --json)" || fail "failed to read main model"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    model:get-main)
      emit_success_from "$resource" "$action" openclaw_cli config get agents.defaults.model --json
      ;;
    provider:set)
      local provider="${1-}"
      local base_url="${2:-}"
      local api_mode="${3:-}"
      require_arg "$provider" "provider"
      [[ -n "$base_url" || -n "$api_mode" ]] || fail "provider set requires at least base_url or api_mode"
      local payload
      local current_payload='{}'
      local current_file
      current_file="$(mktemp)"
      if openclaw_cli config get "models.providers.${provider}" --json >"$current_file" 2>/dev/null; then
        current_payload="$(cat "$current_file")"
      fi
      rm -f "$current_file" >/dev/null 2>&1 || true
      if ! payload="$(build_provider_payload "$current_payload" "$base_url" "$api_mode")"; then
        fail "failed to build provider payload"
      fi
      local patch_result
      local data
      if wait_for_gateway_ready; then
        patch_result="$(gateway_config_patch_json "$(build_provider_patch "$provider" "$payload")")" || fail "failed to apply provider to running gateway"
        data="$(openclaw_cli config get "models.providers.${provider}" --json)" || fail "failed to read provider"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" "$patch_result")"
      else
        run_or_fail "failed to set provider" openclaw_cli config set "models.providers.${provider}" "$payload" --strict-json
        data="$(openclaw_cli config get "models.providers.${provider}" --json)" || fail "failed to read provider"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    provider:get)
      require_arg "${1-}" "provider"
      emit_success_from "$resource" "$action" openclaw_cli config get "models.providers.${1}" --json
      ;;
    provider:delete)
      require_arg "${1-}" "provider"
      local patch_result
      local data='{"deleted":true}'
      if wait_for_gateway_ready; then
        patch_result="$(gateway_config_patch_json "$(build_provider_delete_patch "$1")")" || fail "failed to delete provider from running gateway"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" "$patch_result")"
      else
        run_or_fail "failed to delete provider" openclaw_cli config unset "models.providers.${1}"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    provider:set-api-key)
      require_arg "${1-}" "provider"
      require_arg "${2-}" "api key"
      emit_success_from_runtime_reload "$resource" "$action" auth_profile_json_with_reload set-api-key "$1" "$2" "${3:-}"
      ;;
    provider:get-api-key)
      require_arg "${1-}" "provider"
      emit_success_from "$resource" "$action" auth_profile_json get-api-key "$1" "" "${2:-}"
      ;;
    provider:delete-api-key)
      require_arg "${1-}" "provider"
      emit_success_from_runtime_reload "$resource" "$action" auth_profile_json_with_reload delete-api-key "$1" "" "${2:-}"
      ;;
    gateway:set-local)
      local bind="${1:-lan}"
      local port="${2:-18789}"
      local data
      data="$(openclaw_cli config get gateway --json)" || fail "failed to read gateway config"
      if wait_for_gateway_ready; then
        if gateway_local_is_runtime_noop "$data" "$bind" "$port"; then
          emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" '{"noop":true,"path":null}')"
        else
          fail "gateway bind/port changes require a gateway restart and are not supported as an immediate runtime config action"
        fi
      else
        run_or_fail "failed to set gateway mode" openclaw_cli config set gateway.mode local
        run_or_fail "failed to set gateway bind" openclaw_cli config set gateway.bind "$bind"
        run_or_fail "failed to set gateway port" openclaw_cli config set gateway.port "$port" --strict-json
        data="$(openclaw_cli config get gateway --json)" || fail "failed to read gateway config"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    gateway:get-local)
      emit_success_from "$resource" "$action" openclaw_cli config get gateway --json
      ;;
    gateway:set-token)
      require_arg "${1-}" "token"
      run_or_fail "failed to write gateway token" dotenv_set OPENCLAW_GATEWAY_TOKEN "$1"
      run_or_fail "failed to set gateway auth mode" openclaw_cli config set gateway.auth.mode token
      emit_success_from "$resource" "$action" dotenv_json get OPENCLAW_GATEWAY_TOKEN
      ;;
    gateway:get-token)
      emit_success_from "$resource" "$action" dotenv_json get OPENCLAW_GATEWAY_TOKEN
      ;;
    gateway:delete-token)
      run_or_fail "failed to delete gateway token" dotenv_delete OPENCLAW_GATEWAY_TOKEN
      emit_success_from "$resource" "$action" dotenv_json get OPENCLAW_GATEWAY_TOKEN
      ;;
    workspace:set)
      require_arg "${1-}" "workspace path"
      local patch_result
      local data
      if wait_for_gateway_ready; then
        patch_result="$(gateway_config_patch_json "$(build_workspace_patch "$1")")" || fail "failed to apply workspace to running gateway"
        data="$(openclaw_cli config get agents.defaults.workspace --json)" || fail "failed to read workspace"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_patch "$data" "$patch_result")"
      else
        run_or_fail "failed to set workspace" openclaw_cli config set agents.defaults.workspace "$1"
        data="$(openclaw_cli config get agents.defaults.workspace --json)" || fail "failed to read workspace"
        emit_runtime_success "$resource" "$action" "$(combine_data_with_runtime_skipped "$data")"
      fi
      ;;
    workspace:get)
      emit_success_from "$resource" "$action" openclaw_cli config get agents.defaults.workspace --json
      ;;
    env:set)
      require_arg "${1-}" "key"
      run_or_fail "failed to write env value" dotenv_set "$1" "${2-}"
      emit_success_from "$resource" "$action" dotenv_json get "$1"
      ;;
    env:get)
      require_arg "${1-}" "key"
      emit_success_from "$resource" "$action" dotenv_json get "$1"
      ;;
    env:delete)
      require_arg "${1-}" "key"
      run_or_fail "failed to delete env value" dotenv_delete "$1"
      emit_success_from "$resource" "$action" dotenv_json get "$1"
      ;;
    env:list)
      emit_success_from "$resource" "$action" dotenv_json list
      ;;
    *)
      fail "unknown config command: ${resource} ${action}"
      ;;
  esac
}

main() {
  CURRENT_RESOURCE="${1:-}"
  CURRENT_ACTION="${2:-}"

  [[ -n "$CURRENT_RESOURCE" && -n "$CURRENT_ACTION" ]] || usage

  run_as_agent_script "$@"
  ensure_openclaw_state
  dispatch_config "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
