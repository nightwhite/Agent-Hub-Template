#!/usr/bin/env bash
set -euo pipefail

export AGENT_NAME="${AGENT_NAME:-hermes}"
source /opt/agent/config.sh

export HERMES_HOME="${HERMES_HOME:-/home/agent/.hermes}"
export PATH="/opt/hermes/venv/bin:${PATH}"

run_as_agent() {
  exec runuser -u agent -- env \
    HERMES_HOME="$HERMES_HOME" \
    PATH="$PATH" \
    API_SERVER_ENABLED="${API_SERVER_ENABLED:-}" \
    API_SERVER_HOST="${API_SERVER_HOST:-}" \
    API_SERVER_PORT="${API_SERVER_PORT:-}" \
    API_SERVER_KEY="${API_SERVER_KEY:-}" \
    "$@"
}

start_agent() {
  run_as_agent hermes "$@"
}

main() {
  local command="${1:-gateway}"
  shift || true

  case "$command" in
    shell)
      exec /bin/bash "$@"
      ;;
    config)
      exec /opt/agent/config.sh "$@"
      ;;
    *)
      start_agent "$command" "$@"
      ;;
  esac
}

main "$@"
