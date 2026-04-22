FROM ghcr.io/gitlayzer/ubuntu:22.04-base

ENV HERMES_HOME=/home/agent/.hermes \
    HERMES_SRC=/opt/hermes/src \
    HERMES_VENV=/opt/hermes/venv \
    API_SERVER_ENABLED=true \
    API_SERVER_HOST=0.0.0.0 \
    API_SERVER_PORT=8642 \
    API_SERVER_KEY=change-me-local-dev \
    PATH=/opt/hermes/venv/bin:$PATH

COPY agents/hermes/build.env /tmp/build.env
COPY agents/hermes/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && /tmp/install.sh install \
    && rm -f /tmp/build.env \
    && rm -f /tmp/install.sh

COPY agents/hermes/config.sh /opt/agent/config.sh
COPY agents/hermes/entrypoint.sh /opt/agent/entrypoint.sh
RUN getent group agent >/dev/null || groupadd --gid 10001 agent \
    && id -u agent >/dev/null 2>&1 || useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash agent \
    && chmod +x /opt/agent/config.sh /opt/agent/entrypoint.sh \
    && mkdir -p "$HERMES_HOME" \
    && chown -R agent:agent /opt/agent /opt/hermes /workspace "$HERMES_HOME"

WORKDIR /workspace
VOLUME ["/home/agent/.hermes"]
ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]
CMD ["gateway"]
