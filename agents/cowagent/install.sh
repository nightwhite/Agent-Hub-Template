#!/usr/bin/env bash
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/opt/agent}"
COWAGENT_GIT_URL="${COWAGENT_GIT_URL:-https://github.com/zhayujie/CowAgent.git}"
COWAGENT_REF="${COWAGENT_REF:-2.0.8}"
COWAGENT_SRC="${COWAGENT_SRC:-/opt/cowagent/src}"
COWAGENT_VENV="${COWAGENT_VENV:-/opt/cowagent/venv}"
COWAGENT_HOME="${COWAGENT_HOME:-/home/agent/.cowagent}"
COWAGENT_INSTALL_OPTIONAL="${COWAGENT_INSTALL_OPTIONAL:-true}"
COWAGENT_INSTALL_AGENTMESH="${COWAGENT_INSTALL_AGENTMESH:-true}"
COWAGENT_INSTALL_BROWSER="${COWAGENT_INSTALL_BROWSER:-false}"
COWAGENT_USE_CN_MIRROR="${COWAGENT_USE_CN_MIRROR:-false}"

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
  if [[ "$COWAGENT_USE_CN_MIRROR" == "true" ]]; then
    sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list || true
  fi

  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    espeak \
    ffmpeg \
    git \
    libavcodec-extra \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep
  rm -rf /var/lib/apt/lists/*
}

configure_python_mirror() {
  if [[ "$COWAGENT_USE_CN_MIRROR" == "true" ]]; then
    python3 -m pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
  fi
}

checkout_cowagent_source() {
  rm -rf "$COWAGENT_SRC"
  git clone --depth 1 --branch "$COWAGENT_REF" "$COWAGENT_GIT_URL" "$COWAGENT_SRC"
}

install_cowagent_runtime() {
  mkdir -p /opt/cowagent "$COWAGENT_HOME" "${AGENT_HOME}/bin"

  python3 -m venv "$COWAGENT_VENV"
  "$COWAGENT_VENV/bin/python" -m pip install --upgrade pip setuptools wheel
  "$COWAGENT_VENV/bin/pip" install -r "${COWAGENT_SRC}/requirements.txt"

  if [[ "$COWAGENT_INSTALL_OPTIONAL" == "true" ]]; then
    "$COWAGENT_VENV/bin/pip" install -r "${COWAGENT_SRC}/requirements-optional.txt"
  fi

  if [[ "$COWAGENT_INSTALL_AGENTMESH" == "true" ]]; then
    "$COWAGENT_VENV/bin/pip" install "agentmesh-sdk>=0.1.3"
  fi

  "$COWAGENT_VENV/bin/pip" install -e "$COWAGENT_SRC"

  if [[ "$COWAGENT_INSTALL_BROWSER" == "true" ]]; then
    PLAYWRIGHT_BROWSERS_PATH=/opt/cowagent/ms-playwright "$COWAGENT_VENV/bin/cow" install-browser
  fi
}

write_default_config() {
  "$COWAGENT_VENV/bin/python" - <<'PY'
import json
import os
from pathlib import Path

src = Path(os.environ.get("COWAGENT_SRC", "/opt/cowagent/src"))
template = src / "config-template.json"
target = src / "config.json"

config = json.loads(template.read_text(encoding="utf-8"))
config.update(
    {
        "channel_type": "web",
        "web_port": 9899,
        "agent": True,
        "agent_workspace": "/workspace",
        "appdata_dir": "/home/agent/.cowagent/appdata",
        "speech_recognition": False,
        "group_speech_recognition": False,
    }
)
target.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

install_agent_start() {
  mkdir -p "${AGENT_HOME}/bin"

  cat >"${AGENT_HOME}/bin/start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export COWAGENT_SRC="${COWAGENT_SRC:-/opt/cowagent/src}"
export COWAGENT_HOME="${COWAGENT_HOME:-${AGENT_DATA_DIR:-/home/agent/.cowagent}}"
export COWAGENT_CONFIG_FILE="${COWAGENT_CONFIG_FILE:-${COWAGENT_HOME}/config.json}"
export COWAGENT_VENV="${COWAGENT_VENV:-/opt/cowagent/venv}"
export PATH="${COWAGENT_VENV}/bin:${PATH}"

mkdir -p "$COWAGENT_HOME" "${AGENT_WORKSPACE:-/workspace}"

if [[ ! -f "$COWAGENT_CONFIG_FILE" ]]; then
  cp "${COWAGENT_SRC}/config.json" "$COWAGENT_CONFIG_FILE"
fi

ln -sf "$COWAGENT_CONFIG_FILE" "${COWAGENT_SRC}/config.json"

if [[ -n "${OPENAI_API_KEY:-}" && -z "${OPEN_AI_API_KEY:-}" ]]; then
  export OPEN_AI_API_KEY="$OPENAI_API_KEY"
fi

if [[ -n "${OPENAI_BASE_URL:-}" && -z "${OPEN_AI_API_BASE:-}" ]]; then
  export OPEN_AI_API_BASE="$OPENAI_BASE_URL"
fi

export channel_type="${COWAGENT_CHANNEL_TYPE:-${channel_type:-web}}"
export web_port="${COWAGENT_WEB_PORT:-${WEB_PORT:-${web_port:-${AGENT_PORT:-9899}}}}"
export agent_workspace="${COWAGENT_AGENT_WORKSPACE:-${agent_workspace:-${AGENT_WORKSPACE:-/workspace}}}"
export appdata_dir="${COWAGENT_APPDATA_DIR:-${appdata_dir:-${COWAGENT_HOME}/appdata}}"
export web_password="${COWAGENT_WEB_PASSWORD:-${WEB_PASSWORD:-${web_password:-}}}"
export agent="${COWAGENT_AGENT:-${agent:-true}}"

cd "$COWAGENT_SRC"

if [[ "$#" -eq 0 ]]; then
  exec python app.py
fi

case "$1" in
  app|serve)
    shift
    exec python app.py "$@"
    ;;
  --*)
    exec python app.py "$@"
    ;;
  cow|python|python3|bash|sh)
    exec "$@"
    ;;
  *)
    exec cow "$@"
    ;;
esac
EOF

  chmod +x "${AGENT_HOME}/bin/start"
}

install_agent() {
  prepare_install_env
  install_system_packages
  configure_python_mirror
  checkout_cowagent_source
  install_cowagent_runtime
  write_default_config
  install_agent_start

  if [[ ! -x "${COWAGENT_VENV}/bin/cow" ]]; then
    fail "cow CLI was not installed"
  fi

  if [[ ! -x "${AGENT_HOME}/bin/start" ]]; then
    fail "agent start file was not installed"
  fi
}

dispatch_install_resource() {
  local resource="${1:?missing install resource}"
  shift || true

  case "$resource" in
    agent)
      install_agent "$@"
      ;;
    *)
      fail "unknown install resource: ${resource}"
      ;;
  esac
}

main() {
  local action="${1:-install}"
  local resource="${2:-agent}"

  shift || true
  shift || true

  case "$action" in
    install)
      dispatch_install_resource "$resource" "$@"
      ;;
    *)
      fail "unknown install action: ${action}"
      ;;
  esac
}

main "$@"
