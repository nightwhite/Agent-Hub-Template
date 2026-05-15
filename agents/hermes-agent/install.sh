#!/usr/bin/env bash
set -euo pipefail

HERMES_GIT_URL="${HERMES_GIT_URL:-https://github.com/NousResearch/hermes-agent.git}"
HERMES_BRANCH="${HERMES_BRANCH:-main}"
HERMES_REF="${HERMES_REF:-59b56d445c34e1d4bf797f5345b802c7b5986c72}"
HERMES_HOME="${HERMES_HOME:-/home/agent/.hermes}"
HERMES_SRC="${HERMES_SRC:-/opt/hermes/src}"
HERMES_VENV="${HERMES_VENV:-/opt/hermes/venv}"
AGENT_HOME="${AGENT_HOME:-/opt/agent}"
UV_BIN="${UV_BIN:-/root/.local/bin/uv}"
UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-/opt/uv/python}"

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

fail() {
  printf '[%s] [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  exit 1
}

retry() {
  local max_attempts="${RETRY_MAX_ATTEMPTS:-3}"
  local attempt=1
  local exit_code=0

  while true; do
    if "$@"; then
      return 0
    fi

    exit_code=$?
    if [[ "$attempt" -ge "$max_attempts" ]]; then
      return "$exit_code"
    fi

    log "command failed (attempt ${attempt}/${max_attempts}), retrying: $*"
    sleep $((attempt * 3))
    attempt=$((attempt + 1))
  done
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
  [[ -x "$UV_BIN" ]] || fail "uv was not installed successfully"
}

checkout_hermes_source() {
  rm -rf "$HERMES_SRC"
  retry git -c http.version=HTTP/1.1 clone --branch "$HERMES_BRANCH" --single-branch "$HERMES_GIT_URL" "$HERMES_SRC"
  git -C "$HERMES_SRC" checkout "$HERMES_REF"
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
    cat >"${HERMES_HOME}/config.yaml" <<'CFG'
model:
  default: gpt-5.4
  provider: auto
display:
  skin: default
terminal:
  backend: local
CFG
  fi

  if [[ ! -f "${HERMES_HOME}/.env" ]]; then
    cat >"${HERMES_HOME}/.env" <<'ENVFILE'
# Put Hermes provider credentials here, for example:
# OPENAI_API_KEY=
# OPENROUTER_API_KEY=
# ANTHROPIC_API_KEY=
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
# API_SERVER_KEY is supplied by /opt/agent/bin/start unless overridden at runtime.
ENVFILE
  fi
}

install_agent_start() {
  mkdir -p "${AGENT_HOME}/bin"

  cat >"${AGENT_HOME}/bin/start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export HERMES_HOME="${HERMES_HOME:-${AGENT_DATA_DIR:-/home/agent/.hermes}}"
export HERMES_VENV="${HERMES_VENV:-/opt/hermes/venv}"
export PATH="${HERMES_VENV}/bin:${PATH}"
export API_SERVER_ENABLED="${API_SERVER_ENABLED:-true}"
export API_SERVER_HOST="${API_SERVER_HOST:-0.0.0.0}"
export API_SERVER_PORT="${API_SERVER_PORT:-${AGENT_PORT:-8642}}"
export API_SERVER_KEY="${API_SERVER_KEY:-change-me-local-dev}"

mkdir -p "$HERMES_HOME" "${AGENT_WORKSPACE:-/workspace}"

if [[ "$#" -eq 0 ]]; then
  exec hermes gateway run
fi

case "$1" in
  hermes|python|python3|bash|sh)
    exec "$@"
    ;;
  *)
    exec hermes "$@"
    ;;
esac
EOF

  chmod +x "${AGENT_HOME}/bin/start"
}

install_agent() {
  prepare_install_env
  install_system_packages
  install_uv
  checkout_hermes_source
  install_hermes_runtime
  write_default_config
  install_agent_start

  if [[ ! -x "${HERMES_VENV}/bin/hermes" ]]; then
    fail "hermes binary was not installed"
  fi

  if [[ ! -x "${AGENT_HOME}/bin/start" ]]; then
    fail "agent start file was not installed"
  fi
}

main() {
  local command="${1:-install}"
  shift || true

  case "$command" in
    install|install-agent|agent)
      install_agent "$@"
      ;;
    *)
      fail "unknown install command: ${command}"
      ;;
  esac
}

main "$@"
