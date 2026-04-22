#!/usr/bin/env bash
set -euo pipefail

HERMES_GIT_URL="${HERMES_GIT_URL:-https://github.com/NousResearch/hermes-agent.git}"
HERMES_REF="${HERMES_REF:-v2026.4.16}"
HERMES_HOME="${HERMES_HOME:-/home/agent/.hermes}"
HERMES_SRC="${HERMES_SRC:-/opt/hermes/src}"
HERMES_VENV="${HERMES_VENV:-/opt/hermes/venv}"
UV_BIN="${UV_BIN:-/root/.local/bin/uv}"
UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-/opt/uv/python}"

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  exit 1
}

prepare_install_env() {
  export DEBIAN_FRONTEND=noninteractive
}

install_system_packages() {
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ffmpeg \
    git \
    ripgrep
  rm -rf /var/lib/apt/lists/*
}

install_uv() {
  if [[ -x "$UV_BIN" ]]; then
    return
  fi

  log "installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh

  if [[ ! -x "$UV_BIN" ]]; then
    fail "uv was not installed successfully"
  fi
}

checkout_hermes_source() {
  rm -rf "$HERMES_SRC"
  git clone --depth 1 --branch "$HERMES_REF" "$HERMES_GIT_URL" "$HERMES_SRC"
}

install_hermes_runtime() {
  mkdir -p /opt/hermes /workspace "$HERMES_HOME" "$UV_PYTHON_INSTALL_DIR"
  cd "$HERMES_SRC"

  UV_PYTHON_INSTALL_DIR="$UV_PYTHON_INSTALL_DIR" "$UV_BIN" venv "$HERMES_VENV" --python 3.11

  if [[ -f "uv.lock" ]]; then
    log "installing Hermes with uv.lock"
    UV_PYTHON_INSTALL_DIR="$UV_PYTHON_INSTALL_DIR" UV_PROJECT_ENVIRONMENT="$HERMES_VENV" "$UV_BIN" sync --all-extras --locked || \
      UV_PYTHON_INSTALL_DIR="$UV_PYTHON_INSTALL_DIR" UV_PROJECT_ENVIRONMENT="$HERMES_VENV" "$UV_BIN" pip install -e ".[all]" || \
      UV_PYTHON_INSTALL_DIR="$UV_PYTHON_INSTALL_DIR" UV_PROJECT_ENVIRONMENT="$HERMES_VENV" "$UV_BIN" pip install -e "."
  else
    log "installing Hermes with uv pip"
    UV_PYTHON_INSTALL_DIR="$UV_PYTHON_INSTALL_DIR" UV_PROJECT_ENVIRONMENT="$HERMES_VENV" "$UV_BIN" pip install -e ".[all]" || \
      UV_PYTHON_INSTALL_DIR="$UV_PYTHON_INSTALL_DIR" UV_PROJECT_ENVIRONMENT="$HERMES_VENV" "$UV_BIN" pip install -e "."
  fi
}

write_default_config() {
  mkdir -p "$HERMES_HOME"

  if [[ ! -f "${HERMES_HOME}/config.yaml" ]]; then
    cat >"${HERMES_HOME}/config.yaml" <<'EOF'
model: gpt-5.4
provider: custom
display:
  skin: default
terminal:
  backend: local
EOF
  fi

  if [[ ! -f "${HERMES_HOME}/.env" ]]; then
    cat >"${HERMES_HOME}/.env" <<'EOF'
# Populate provider credentials or endpoint configuration before first real use.
# Example custom endpoint values:
# OPENAI_API_KEY=
# OPENAI_BASE_URL=
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
API_SERVER_KEY=change-me-local-dev
EOF
  fi
}

install_agent() {
  prepare_install_env
  install_system_packages
  install_uv
  checkout_hermes_source
  install_hermes_runtime
  write_default_config

  if [[ ! -x "${HERMES_VENV}/bin/hermes" ]]; then
    fail "hermes binary was not installed"
  fi
}

main() {
  local command="${1:-install}"
  shift || true

  case "$command" in
    install)
      install_agent "$@"
      ;;
    *)
      printf 'unknown install command: %s\n' "$command" >&2
      exit 1
      ;;
  esac
}

main "$@"
