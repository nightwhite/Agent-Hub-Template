#!/usr/bin/env bash
set -euo pipefail

source /opt/agent/lib/common.sh

export HERMES_HOME="${HERMES_HOME:-/home/agent/.hermes}"
export PATH="/opt/hermes/venv/bin:${PATH}"

mode="${1:-chat}"

case "$mode" in
  shell)
    shift || true
    log "starting interactive shell"
    exec /bin/bash "$@"
    ;;
  hermes)
    shift || true
    exec hermes "$@"
    ;;
  *)
    exec hermes "$@"
    ;;
esac
