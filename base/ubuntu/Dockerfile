ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive     LANG=C.UTF-8     LC_ALL=C.UTF-8

COPY base/ubuntu/packages.txt /tmp/packages.txt

RUN apt-get update     && xargs -r apt-get install -y --no-install-recommends < /tmp/packages.txt     && rm -rf /var/lib/apt/lists/* /tmp/packages.txt

RUN groupadd --gid 10001 agent     && useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash agent     && mkdir -p /opt/agent /workspace     && chown -R agent:agent /opt/agent /workspace

WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash"]
