#!/usr/bin/env bash
set -euo pipefail

source /opt/agent/lib/common.sh

if [[ $# -eq 0 ]]; then
  warn "No command provided; starting interactive shell"
  exec /bin/bash
fi

log "Executing command: $*"
exec "$@"
