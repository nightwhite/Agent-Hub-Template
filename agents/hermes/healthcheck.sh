#!/usr/bin/env bash
set -euo pipefail

export HERMES_HOME="${HERMES_HOME:-/home/agent/.hermes}"
export PATH="/opt/hermes/venv/bin:${PATH}"

hermes version >/dev/null
