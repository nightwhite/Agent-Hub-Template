#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-hermes}"
HERMES_CONFIG_HOME="${HERMES_CONFIG_HOME:-/home/agent/.hermes}"
HERMES_DOTENV_FILE="${HERMES_DOTENV_FILE:-${HERMES_CONFIG_HOME}/.env}"
HERMES_STATE_ENV_FILE="${HERMES_STATE_ENV_FILE:-${HERMES_CONFIG_HOME}/config.values.env}"
HERMES_PROVIDERS_FILE="${HERMES_PROVIDERS_FILE:-${HERMES_CONFIG_HOME}/providers.list}"
HERMES_CONFIG_FILE="${HERMES_CONFIG_FILE:-${HERMES_CONFIG_HOME}/config.yaml}"

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  exit 1
}

ensure_config_store() {
  mkdir -p "$HERMES_CONFIG_HOME"
  touch "$HERMES_DOTENV_FILE" "$HERMES_STATE_ENV_FILE" "$HERMES_PROVIDERS_FILE"
}

dotenv_set() {
  local key="${1:?missing key}"
  local value="${2:-}"
  local temp_file
  local found=0

  ensure_config_store
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${key}="* ]]; then
      printf '%s=%s\n' "$key" "$value" >>"$temp_file"
      found=1
    else
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$HERMES_DOTENV_FILE"

  if [[ "$found" -eq 0 ]]; then
    printf '%s=%s\n' "$key" "$value" >>"$temp_file"
  fi

  mv "$temp_file" "$HERMES_DOTENV_FILE"
}

dotenv_delete() {
  local key="${1:?missing key}"
  local temp_file

  ensure_config_store
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" != "${key}="* ]]; then
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$HERMES_DOTENV_FILE"

  mv "$temp_file" "$HERMES_DOTENV_FILE"
}

load_yaml_state() {
  HERMES_MODEL="gpt-5.4"
  HERMES_MODEL_SET=0
  HERMES_PROVIDER="custom"
  HERMES_PROVIDER_SET=0
  HERMES_TERMINAL_BACKEND="local"
  HERMES_TERMINAL_BACKEND_SET=0
  HERMES_DISPLAY_SKIN="default"
  HERMES_DISPLAY_SKIN_SET=0
  HERMES_FALLBACK_PROVIDERS=""
  HERMES_FALLBACK_PROVIDERS_SET=0

  ensure_config_store
  # shellcheck disable=SC1090
  source "$HERMES_STATE_ENV_FILE"
}

save_yaml_state() {
  ensure_config_store
  cat >"$HERMES_STATE_ENV_FILE" <<EOF
HERMES_MODEL=$(printf '%q' "${HERMES_MODEL}")
HERMES_MODEL_SET=$(printf '%q' "${HERMES_MODEL_SET}")
HERMES_PROVIDER=$(printf '%q' "${HERMES_PROVIDER}")
HERMES_PROVIDER_SET=$(printf '%q' "${HERMES_PROVIDER_SET}")
HERMES_TERMINAL_BACKEND=$(printf '%q' "${HERMES_TERMINAL_BACKEND}")
HERMES_TERMINAL_BACKEND_SET=$(printf '%q' "${HERMES_TERMINAL_BACKEND_SET}")
HERMES_DISPLAY_SKIN=$(printf '%q' "${HERMES_DISPLAY_SKIN}")
HERMES_DISPLAY_SKIN_SET=$(printf '%q' "${HERMES_DISPLAY_SKIN_SET}")
HERMES_FALLBACK_PROVIDERS=$(printf '%q' "${HERMES_FALLBACK_PROVIDERS}")
HERMES_FALLBACK_PROVIDERS_SET=$(printf '%q' "${HERMES_FALLBACK_PROVIDERS_SET}")
EOF
}

yaml_quote() {
  local value="${1:-}"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

list_contains_csv() {
  local csv="${1:-}"
  local needle="${2:?missing needle}"
  local item

  IFS=',' read -r -a items <<<"$csv"
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || continue
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

append_csv_unique() {
  local csv="${1:-}"
  local item="${2:?missing item}"

  if [[ -z "$csv" ]]; then
    printf '%s' "$item"
    return
  fi

  if list_contains_csv "$csv" "$item"; then
    printf '%s' "$csv"
    return
  fi

  printf '%s,%s' "$csv" "$item"
}

remove_csv_item() {
  local csv="${1:-}"
  local needle="${2:?missing item}"
  local result=""
  local item

  IFS=',' read -r -a items <<<"$csv"
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || continue
    if [[ "$item" == "$needle" ]]; then
      continue
    fi
    if [[ -z "$result" ]]; then
      result="$item"
    else
      result="${result},${item}"
    fi
  done

  printf '%s' "$result"
}

provider_add() {
  local name="${1:?missing provider name}"
  local base_url="${2:-}"
  local api_key_env="${3:-OPENAI_API_KEY}"
  local temp_file
  local found=0

  ensure_config_store
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      continue
    fi
    IFS=$'\t' read -r current_name _ _ <<<"$line"
    if [[ "$current_name" == "$name" ]]; then
      printf '%s\t%s\t%s\n' "$name" "$base_url" "$api_key_env" >>"$temp_file"
      found=1
    else
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$HERMES_PROVIDERS_FILE"

  if [[ "$found" -eq 0 ]]; then
    printf '%s\t%s\t%s\n' "$name" "$base_url" "$api_key_env" >>"$temp_file"
  fi

  mv "$temp_file" "$HERMES_PROVIDERS_FILE"
}

provider_remove() {
  local name="${1:?missing provider name}"
  local temp_file

  ensure_config_store
  temp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      continue
    fi
    IFS=$'\t' read -r current_name _ _ <<<"$line"
    if [[ "$current_name" != "$name" ]]; then
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$HERMES_PROVIDERS_FILE"

  mv "$temp_file" "$HERMES_PROVIDERS_FILE"
}

provider_list() {
  ensure_config_store
  cat "$HERMES_PROVIDERS_FILE"
}

render_config_yaml() {
  local item

  load_yaml_state
  ensure_config_store

  {
    if [[ "${HERMES_MODEL_SET:-0}" == "1" ]]; then
      printf 'model: %s\n' "$(yaml_quote "$HERMES_MODEL")"
    fi

    if [[ "${HERMES_PROVIDER_SET:-0}" == "1" ]]; then
      printf 'provider: %s\n' "$(yaml_quote "$HERMES_PROVIDER")"
    fi

    if [[ "${HERMES_DISPLAY_SKIN_SET:-0}" == "1" ]]; then
      printf 'display:\n'
      printf '  skin: %s\n' "$(yaml_quote "$HERMES_DISPLAY_SKIN")"
    fi

    if [[ "${HERMES_TERMINAL_BACKEND_SET:-0}" == "1" ]]; then
      printf 'terminal:\n'
      printf '  backend: %s\n' "$(yaml_quote "$HERMES_TERMINAL_BACKEND")"
    fi

    if [[ "${HERMES_FALLBACK_PROVIDERS_SET:-0}" == "1" && -n "$HERMES_FALLBACK_PROVIDERS" ]]; then
      printf 'fallback_providers:\n'
      IFS=',' read -r -a items <<<"$HERMES_FALLBACK_PROVIDERS"
      for item in "${items[@]}"; do
        [[ -n "$item" ]] || continue
        printf '  - %s\n' "$(yaml_quote "$item")"
      done
    fi

    if [[ -s "$HERMES_PROVIDERS_FILE" ]]; then
      printf 'providers:\n'
      while IFS=$'\t' read -r name base_url api_key_env || [[ -n "$name" ]]; do
        [[ -n "$name" ]] || continue
        printf '  - name: %s\n' "$(yaml_quote "$name")"
        [[ -n "$base_url" ]] && printf '    base_url: %s\n' "$(yaml_quote "$base_url")"
        [[ -n "$api_key_env" ]] && printf '    api_key_env: %s\n' "$(yaml_quote "$api_key_env")"
      done <"$HERMES_PROVIDERS_FILE"
    fi
  } >"$HERMES_CONFIG_FILE"
}

set_config() {
  local endpoint="${1:?missing endpoint}"
  local api_key="${2:?missing api key}"
  local model="${3:-gpt-5.4}"

  dotenv_set OPENAI_BASE_URL "$endpoint"
  dotenv_set OPENAI_API_KEY "$api_key"

  load_yaml_state
  HERMES_MODEL="$model"
  HERMES_MODEL_SET=1
  save_yaml_state
  render_config_yaml

  log "updated Hermes runtime config"
}

get_config() {
  ensure_config_store
  printf '[dotenv]\n'
  cat "$HERMES_DOTENV_FILE"
  printf '\n[yaml_state]\n'
  cat "$HERMES_STATE_ENV_FILE"
  printf '\n[providers]\n'
  cat "$HERMES_PROVIDERS_FILE"
}

delete_config() {
  rm -f "$HERMES_DOTENV_FILE" "$HERMES_STATE_ENV_FILE" "$HERMES_PROVIDERS_FILE" "$HERMES_CONFIG_FILE"
  log "deleted Hermes runtime config"
}

list_config() {
  get_config "$@"
}

set_yaml_value() {
  local key="${1:?missing key}"
  local value="${2:?missing value}"

  load_yaml_state

  case "$key" in
    model)
      HERMES_MODEL="$value"
      HERMES_MODEL_SET=1
      ;;
    provider)
      HERMES_PROVIDER="$value"
      HERMES_PROVIDER_SET=1
      ;;
    terminal.backend)
      HERMES_TERMINAL_BACKEND="$value"
      HERMES_TERMINAL_BACKEND_SET=1
      ;;
    display.skin)
      HERMES_DISPLAY_SKIN="$value"
      HERMES_DISPLAY_SKIN_SET=1
      ;;
    *)
      fail "unsupported yaml key: ${key}"
      ;;
  esac

  save_yaml_state
  render_config_yaml
  log "updated yaml key: ${key}"
}

get_yaml_value() {
  local key="${1:?missing key}"

  load_yaml_state

  case "$key" in
    model)
      printf '%s\n' "$HERMES_MODEL"
      ;;
    provider)
      printf '%s\n' "$HERMES_PROVIDER"
      ;;
    terminal.backend)
      printf '%s\n' "$HERMES_TERMINAL_BACKEND"
      ;;
    display.skin)
      printf '%s\n' "$HERMES_DISPLAY_SKIN"
      ;;
    fallback_providers)
      printf '%s\n' "$HERMES_FALLBACK_PROVIDERS"
      ;;
    *)
      fail "unsupported yaml key: ${key}"
      ;;
  esac
}

delete_yaml_value() {
  local key="${1:?missing key}"

  load_yaml_state

  case "$key" in
    model)
      HERMES_MODEL="gpt-5.4"
      HERMES_MODEL_SET=0
      ;;
    provider)
      HERMES_PROVIDER="custom"
      HERMES_PROVIDER_SET=0
      ;;
    terminal.backend)
      HERMES_TERMINAL_BACKEND="local"
      HERMES_TERMINAL_BACKEND_SET=0
      ;;
    display.skin)
      HERMES_DISPLAY_SKIN="default"
      HERMES_DISPLAY_SKIN_SET=0
      ;;
    fallback_providers)
      HERMES_FALLBACK_PROVIDERS=""
      HERMES_FALLBACK_PROVIDERS_SET=0
      ;;
    *)
      fail "unsupported yaml key: ${key}"
      ;;
  esac

  save_yaml_state
  render_config_yaml
  log "deleted yaml key: ${key}"
}

add_yaml_value() {
  local key="${1:?missing key}"
  shift || true

  load_yaml_state

  case "$key" in
    fallback_providers)
      HERMES_FALLBACK_PROVIDERS="$(append_csv_unique "$HERMES_FALLBACK_PROVIDERS" "${1:?missing fallback provider}")"
      HERMES_FALLBACK_PROVIDERS_SET=1
      save_yaml_state
      render_config_yaml
      log "added fallback provider: ${1}"
      ;;
    provider)
      provider_add "${1:?missing provider name}" "${2:-}" "${3:-OPENAI_API_KEY}"
      render_config_yaml
      log "added provider: ${1}"
      ;;
    *)
      fail "unsupported add target: ${key}"
      ;;
  esac
}

remove_yaml_value() {
  local key="${1:?missing key}"
  shift || true

  load_yaml_state

  case "$key" in
    fallback_providers)
      HERMES_FALLBACK_PROVIDERS="$(remove_csv_item "$HERMES_FALLBACK_PROVIDERS" "${1:?missing fallback provider}")"
      save_yaml_state
      render_config_yaml
      log "removed fallback provider: ${1}"
      ;;
    provider)
      provider_remove "${1:?missing provider name}"
      render_config_yaml
      log "removed provider: ${1}"
      ;;
    *)
      fail "unsupported remove target: ${key}"
      ;;
  esac
}

list_yaml_values() {
  render_config_yaml
  cat "$HERMES_CONFIG_FILE"
}

dispatch_config_action() {
  local action="${1:?missing action}"
  local resource="${2:-config}"
  shift || true
  shift || true

  case "$resource" in
    config)
      case "$action" in
        set) set_config "$@" ;;
        get) get_config "$@" ;;
        delete) delete_config "$@" ;;
        list) list_config "$@" ;;
        *)
          fail "unknown config action: ${action}"
          ;;
      esac
      ;;
    yaml)
      case "$action" in
        set) set_yaml_value "$@" ;;
        get) get_yaml_value "$@" ;;
        delete) delete_yaml_value "$@" ;;
        list) list_yaml_values "$@" ;;
        add) add_yaml_value "$@" ;;
        remove) remove_yaml_value "$@" ;;
        render) render_config_yaml ;;
        *)
          fail "unknown yaml action: ${action}"
          ;;
      esac
      ;;
    *)
      fail "unknown config resource: ${resource}"
      ;;
  esac
}

main() {
  local action="${1:-list}"
  local resource="${2:-config}"

  dispatch_config_action "$action" "$resource" "${@:3}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
