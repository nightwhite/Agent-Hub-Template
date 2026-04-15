#!/usr/bin/env bash
set -euo pipefail

source /opt/agent/lib/common.sh

export CHANGE_ME_HOME="${CHANGE_ME_HOME:-/home/agent/.change-me}"
mkdir -p "$CHANGE_ME_HOME"

mode="${1:-shell}"
case "$mode" in
  shell)
    shift || true
    if [[ $# -gt 0 ]]; then
      exec /bin/bash "$@"
    fi
    exec /bin/bash
    ;;
  run)
    shift || true
    exec /opt/change-me/bin/change-me-run "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
