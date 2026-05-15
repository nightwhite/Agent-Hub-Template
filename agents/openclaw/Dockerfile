ARG BASE_PLATFORM=linux/amd64
FROM --platform=${BASE_PLATFORM} ghcr.io/gitlayzer/ubuntu:22.04-base

ARG http_proxy
ARG https_proxy
ARG all_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG ALL_PROXY
ARG no_proxy
ARG NO_PROXY

ENV AGENT_NAME=openclaw \
    AGENT_HOME=/opt/agent \
    AGENT_DATA_DIR=/home/agent/.openclaw \
    AGENT_WORKSPACE=/workspace \
    AGENT_PORT=18789 \
    AGENT_LOG_LEVEL=info \
    OPENCLAW_STATE_DIR=/home/agent/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/agent/.openclaw/openclaw.json \
    OPENCLAW_WORKSPACE=/workspace \
    OPENCLAW_PLUGIN_STAGE_DIR=/opt/openclaw/plugin-runtime-deps \
    PATH=/opt/agent/bin:/usr/local/bin:$PATH

COPY agents/openclaw/build.env /tmp/build.env
COPY agents/openclaw/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && /tmp/install.sh install \
    && rm -f /tmp/build.env /tmp/install.sh

COPY agents/openclaw/entrypoint.sh /opt/agent/entrypoint.sh
RUN getent group agent >/dev/null || groupadd --gid 10001 agent \
    && id -u agent >/dev/null 2>&1 || useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash agent \
    && chmod +x /opt/agent/entrypoint.sh \
    && mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_PLUGIN_STAGE_DIR" "$AGENT_WORKSPACE" \
    && chown -R agent:agent /opt/agent "$OPENCLAW_STATE_DIR" "$OPENCLAW_PLUGIN_STAGE_DIR" "$AGENT_WORKSPACE" /home/agent

RUN runuser -u agent -- env \
      HOME=/home/agent \
      OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
      OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
      OPENCLAW_WORKSPACE="$OPENCLAW_WORKSPACE" \
      OPENCLAW_PLUGIN_STAGE_DIR="$OPENCLAW_PLUGIN_STAGE_DIR" \
      PATH="$PATH" \
      openclaw doctor --repair --non-interactive

WORKDIR ${AGENT_WORKSPACE}
VOLUME ["/workspace", "/home/agent/.openclaw"]
EXPOSE 18789
ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]
CMD ["start"]
