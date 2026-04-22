#!/usr/bin/env bash
set -euo pipefail

export AGENT_NAME="${AGENT_NAME:-change-me}"
source /opt/agent/config.sh

export CHANGE_ME_HOME="${CHANGE_ME_HOME:-/home/agent/.change-me}"
mkdir -p "$CHANGE_ME_HOME"

run_as_agent() {
  exec runuser -u agent -- "$@"
}

start_agent() {
  run_as_agent /opt/change-me/bin/change-me-run "$@"
}

main() {
  local command="${1:-start}"
  shift || true

  case "$command" in
    shell)
      exec /bin/bash "$@"
      ;;
    config)
      exec /opt/agent/config.sh "$@"
      ;;
    start)
      start_agent "$@"
      ;;
    *)
      start_agent "$command" "$@"
      ;;
  esac
}

main "$@"
