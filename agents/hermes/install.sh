#!/usr/bin/env bash
set -euo pipefail

: "${HERMES_GIT_URL:?HERMES_GIT_URL is required}"
: "${HERMES_REF:?HERMES_REF is required}"
: "${HERMES_EXTRAS:?HERMES_EXTRAS is required}"

export DEBIAN_FRONTEND=noninteractive

mkdir -p /opt/agent/lib /opt/hermes /workspace /home/agent/.hermes

python3 -m venv /opt/hermes/venv
source /opt/hermes/venv/bin/activate

python -m pip install --upgrade pip setuptools wheel

git clone --depth 1 --branch "$HERMES_REF" "$HERMES_GIT_URL" /opt/hermes/src
cd /opt/hermes/src

python -m pip install --no-cache-dir ".[${HERMES_EXTRAS}]"

mkdir -p /home/agent/.hermes
if [[ ! -f /home/agent/.hermes/config.yaml ]]; then
  cat >/home/agent/.hermes/config.yaml <<'EOF'
model: gpt-5.4
provider: custom
display:
  skin: default
terminal:
  backend: local
EOF
fi

if [[ ! -f /home/agent/.hermes/.env ]]; then
  cat >/home/agent/.hermes/.env <<'EOF'
# Populate provider credentials or endpoint configuration before first real use.
# Example custom endpoint values:
# OPENAI_API_KEY=
# OPENAI_BASE_URL=
EOF
fi
