ARG BASE_IMAGE=agent-hub/base-ubuntu:dev
FROM ${BASE_IMAGE}

ARG HERMES_GIT_URL=https://github.com/NousResearch/hermes-agent.git
ARG HERMES_REF=v2026.4.13
ARG HERMES_EXTRAS=cron,cli,pty,mcp,acp,web

ENV HERMES_HOME=/home/agent/.hermes \
    HERMES_SRC=/opt/hermes/src \
    HERMES_VENV=/opt/hermes/venv \
    PATH=/opt/hermes/venv/bin:$PATH

COPY shared/scripts/common.sh /opt/agent/lib/common.sh
COPY agents/hermes/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && HERMES_GIT_URL="$HERMES_GIT_URL" HERMES_REF="$HERMES_REF" HERMES_EXTRAS="$HERMES_EXTRAS" /tmp/install.sh \
    && rm -f /tmp/install.sh

COPY agents/hermes/entrypoint.sh /opt/agent/entrypoint.sh
COPY agents/hermes/healthcheck.sh /opt/agent/healthcheck.sh
RUN chmod +x /opt/agent/lib/common.sh /opt/agent/entrypoint.sh /opt/agent/healthcheck.sh \
    && mkdir -p "$HERMES_HOME" \
    && chown -R agent:agent /opt/agent /opt/hermes /workspace "$HERMES_HOME"

USER agent
WORKDIR /workspace
VOLUME ["/home/agent/.hermes"]
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 CMD ["/opt/agent/healthcheck.sh"]
ENTRYPOINT ["/opt/agent/entrypoint.sh"]
CMD ["chat"]
