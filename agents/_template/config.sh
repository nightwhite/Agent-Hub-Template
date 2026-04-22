#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-change-me}"
AGENT_CONFIG_HOME="${AGENT_CONFIG_HOME:-/home/agent/.config/${AGENT_NAME}}"
AGENT_DOTENV_FILE="${AGENT_DOTENV_FILE:-${AGENT_CONFIG_HOME}/.env}"
AGENT_STATE_ENV_FILE="${AGENT_STATE_ENV_FILE:-${AGENT_CONFIG_HOME}/config.values.env}"
AGENT_LIST_FILE="${AGENT_LIST_FILE:-${AGENT_CONFIG_HOME}/items.list}"
AGENT_CONFIG_FILE="${AGENT_CONFIG_FILE:-${AGENT_CONFIG_HOME}/config.yaml}"

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  exit 1
}

ensure_config_store() {
  mkdir -p "$AGENT_CONFIG_HOME"
  touch "$AGENT_DOTENV_FILE" "$AGENT_STATE_ENV_FILE" "$AGENT_LIST_FILE"
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
  done <"$AGENT_DOTENV_FILE"

  if [[ "$found" -eq 0 ]]; then
    printf '%s=%s\n' "$key" "$value" >>"$temp_file"
  fi

  mv "$temp_file" "$AGENT_DOTENV_FILE"
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
  done <"$AGENT_DOTENV_FILE"

  mv "$temp_file" "$AGENT_DOTENV_FILE"
}

load_yaml_state() {
  TEMPLATE_MAIN_VALUE="replace-me"
  TEMPLATE_SECONDARY_VALUE="replace-me"
  TEMPLATE_LIST_VALUES=""

  ensure_config_store
  # shellcheck disable=SC1090
  source "$AGENT_STATE_ENV_FILE"
}

save_yaml_state() {
  ensure_config_store
  cat >"$AGENT_STATE_ENV_FILE" <<EOF
TEMPLATE_MAIN_VALUE=$(printf '%q' "${TEMPLATE_MAIN_VALUE}")
TEMPLATE_SECONDARY_VALUE=$(printf '%q' "${TEMPLATE_SECONDARY_VALUE}")
TEMPLATE_LIST_VALUES=$(printf '%q' "${TEMPLATE_LIST_VALUES}")
EOF
}

yaml_quote() {
  local value="${1:-}"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

list_contains_csv() {
  local csv="${1:-}"
  local needle="${2:?missing item}"
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

list_item_add() {
  local name="${1:?missing item name}"
  local value1="${2:-}"
  local value2="${3:-}"
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
      printf '%s\t%s\t%s\n' "$name" "$value1" "$value2" >>"$temp_file"
      found=1
    else
      printf '%s\n' "$line" >>"$temp_file"
    fi
  done <"$AGENT_LIST_FILE"

  if [[ "$found" -eq 0 ]]; then
    printf '%s\t%s\t%s\n' "$name" "$value1" "$value2" >>"$temp_file"
  fi

  mv "$temp_file" "$AGENT_LIST_FILE"
}

list_item_remove() {
  local name="${1:?missing item name}"
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
  done <"$AGENT_LIST_FILE"

  mv "$temp_file" "$AGENT_LIST_FILE"
}

render_config_yaml() {
  local item

  load_yaml_state
  ensure_config_store

  {
    printf '# Template-generated config.yaml for %s\n' "$AGENT_NAME"
    printf '# Replace the placeholder keys and structure for your real agent.\n'
    printf 'main_value: %s\n' "$(yaml_quote "$TEMPLATE_MAIN_VALUE")"
    printf 'secondary_value: %s\n' "$(yaml_quote "$TEMPLATE_SECONDARY_VALUE")"

    if [[ -n "$TEMPLATE_LIST_VALUES" ]]; then
      printf 'list_values:\n'
      IFS=',' read -r -a items <<<"$TEMPLATE_LIST_VALUES"
      for item in "${items[@]}"; do
        [[ -n "$item" ]] || continue
        printf '  - %s\n' "$(yaml_quote "$item")"
      done
    fi

    if [[ -s "$AGENT_LIST_FILE" ]]; then
      printf 'items:\n'
      while IFS=$'\t' read -r name value1 value2 || [[ -n "$name" ]]; do
        [[ -n "$name" ]] || continue
        printf '  - name: %s\n' "$(yaml_quote "$name")"
        [[ -n "$value1" ]] && printf '    value1: %s\n' "$(yaml_quote "$value1")"
        [[ -n "$value2" ]] && printf '    value2: %s\n' "$(yaml_quote "$value2")"
      done <"$AGENT_LIST_FILE"
    fi
  } >"$AGENT_CONFIG_FILE"
}

set_config() {
  local key="${1:?missing key}"
  local value="${2:-}"

  dotenv_set "$key" "$value"
  log "updated runtime env key: ${key}"
}

get_config() {
  ensure_config_store
  printf '[dotenv]\n'
  cat "$AGENT_DOTENV_FILE"
  printf '\n[yaml_state]\n'
  cat "$AGENT_STATE_ENV_FILE"
  printf '\n[list_items]\n'
  cat "$AGENT_LIST_FILE"
}

delete_config() {
  rm -f "$AGENT_DOTENV_FILE" "$AGENT_STATE_ENV_FILE" "$AGENT_LIST_FILE" "$AGENT_CONFIG_FILE"
  log "deleted template config store"
}

list_config() {
  get_config "$@"
}

set_yaml_value() {
  local key="${1:?missing key}"
  local value="${2:?missing value}"

  load_yaml_state

  case "$key" in
    main_value)
      TEMPLATE_MAIN_VALUE="$value"
      ;;
    secondary_value)
      TEMPLATE_SECONDARY_VALUE="$value"
      ;;
    *)
      fail "unsupported template yaml key: ${key}"
      ;;
  esac

  save_yaml_state
  render_config_yaml
  log "updated template yaml key: ${key}"
}

get_yaml_value() {
  local key="${1:?missing key}"

  load_yaml_state

  case "$key" in
    main_value)
      printf '%s\n' "$TEMPLATE_MAIN_VALUE"
      ;;
    secondary_value)
      printf '%s\n' "$TEMPLATE_SECONDARY_VALUE"
      ;;
    list_values)
      printf '%s\n' "$TEMPLATE_LIST_VALUES"
      ;;
    *)
      fail "unsupported template yaml key: ${key}"
      ;;
  esac
}

delete_yaml_value() {
  local key="${1:?missing key}"

  load_yaml_state

  case "$key" in
    main_value)
      TEMPLATE_MAIN_VALUE="replace-me"
      ;;
    secondary_value)
      TEMPLATE_SECONDARY_VALUE="replace-me"
      ;;
    list_values)
      TEMPLATE_LIST_VALUES=""
      ;;
    *)
      fail "unsupported template yaml key: ${key}"
      ;;
  esac

  save_yaml_state
  render_config_yaml
  log "deleted template yaml key: ${key}"
}

add_yaml_value() {
  local key="${1:?missing key}"
  shift || true

  load_yaml_state

  case "$key" in
    list_values)
      TEMPLATE_LIST_VALUES="$(append_csv_unique "$TEMPLATE_LIST_VALUES" "${1:?missing list item}")"
      save_yaml_state
      render_config_yaml
      log "added template list item: ${1}"
      ;;
    item)
      list_item_add "${1:?missing item name}" "${2:-}" "${3:-}"
      render_config_yaml
      log "added template item: ${1}"
      ;;
    *)
      fail "unsupported template add target: ${key}"
      ;;
  esac
}

remove_yaml_value() {
  local key="${1:?missing key}"
  shift || true

  load_yaml_state

  case "$key" in
    list_values)
      TEMPLATE_LIST_VALUES="$(remove_csv_item "$TEMPLATE_LIST_VALUES" "${1:?missing list item}")"
      save_yaml_state
      render_config_yaml
      log "removed template list item: ${1}"
      ;;
    item)
      list_item_remove "${1:?missing item name}"
      render_config_yaml
      log "removed template item: ${1}"
      ;;
    *)
      fail "unsupported template remove target: ${key}"
      ;;
  esac
}

list_yaml_values() {
  render_config_yaml
  cat "$AGENT_CONFIG_FILE"
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
