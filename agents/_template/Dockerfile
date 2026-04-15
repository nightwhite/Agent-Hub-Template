ARG BASE_IMAGE=agent-hub/base-ubuntu:dev
FROM ${BASE_IMAGE}

ARG AGENT_HOME=/opt/change-me
ENV AGENT_HOME=${AGENT_HOME}

COPY shared/scripts/common.sh /opt/agent/lib/common.sh
COPY agents/change-me/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh     && /tmp/install.sh     && rm -f /tmp/install.sh

COPY agents/change-me/entrypoint.sh /opt/agent/entrypoint.sh
COPY agents/change-me/healthcheck.sh /opt/agent/healthcheck.sh
RUN chmod +x /opt/agent/lib/common.sh /opt/agent/entrypoint.sh /opt/agent/healthcheck.sh     && mkdir -p /workspace ${AGENT_HOME} /home/agent/.change-me     && chown -R agent:agent /opt/agent ${AGENT_HOME} /workspace /home/agent/.change-me

USER agent
WORKDIR /workspace
VOLUME ["/workspace"]
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 CMD ["/opt/agent/healthcheck.sh"]
ENTRYPOINT ["/opt/agent/entrypoint.sh"]
CMD ["shell"]
