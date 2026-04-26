#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-hermes-agent}"
HERMES_HOME="${HERMES_HOME:-/home/agent/.hermes}"
HERMES_VENV="${HERMES_VENV:-/opt/hermes/venv}"
PATH="${HERMES_VENV}/bin:${PATH}"

# shellcheck disable=SC1091
source /opt/agent/config.sh

fail() {
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  exit 1
}

run_as_agent() {
  exec runuser -u agent -- env \
    HOME=/home/agent \
    HERMES_HOME="$HERMES_HOME" \
    HERMES_VENV="$HERMES_VENV" \
    PATH="$PATH" \
    API_SERVER_ENABLED="${API_SERVER_ENABLED:-}" \
    API_SERVER_HOST="${API_SERVER_HOST:-}" \
    API_SERVER_PORT="${API_SERVER_PORT:-}" \
    API_SERVER_KEY="${API_SERVER_KEY:-}" \
    "$@"
}

start_agent() {
  [[ "$#" -eq 0 ]] || fail "hermes start does not accept extra arguments in phase 1"
  run_as_agent hermes gateway run
}

run_agent_cli() {
  [[ "$#" -gt 0 ]] || fail "hermes run requires native CLI arguments"
  run_as_agent hermes "$@"
}

main() {
  local command="${1:-start}"
  shift || true

  ensure_hermes_state

  case "$command" in
    start)
      start_agent "$@"
      ;;
    run)
      run_agent_cli "$@"
      ;;
    config)
      exec /opt/agent/config.sh "$@"
      ;;
    shell)
      exec /bin/bash "$@"
      ;;
    *)
      fail "unknown command: ${command}. expected one of: start, run, config, shell"
      ;;
  esac
}

main "$@"
