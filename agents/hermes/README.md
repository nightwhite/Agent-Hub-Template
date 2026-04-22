# Hermes Agent image

This image installs the real Hermes Agent from the official NousResearch/hermes-agent source repository.

The install flow in this repo follows the current official setup direction:

- install `uv`
- create a Python 3.11 virtual environment
- prefer `uv sync --all-extras --locked` when `uv.lock` is present
- fall back to `uv pip install -e ".[all]"` when lockfile sync is unavailable
- preserve the base image `/init` entrypoint and pass `/opt/agent/entrypoint.sh` as the container command

Files in this directory:

- `Dockerfile`: builds the runtime image from `ghcr.io/gitlayzer/ubuntu:22.04-base`
- `build.env`: build-time environment values loaded before `install.sh`
- `install.sh`: installs the Hermes runtime during image build
- `config.sh`: handles runtime config commands such as `set config ...` and `get config`
- `config.json`: frontend schema for rendering config actions
- `entrypoint.sh`: starts the Hermes runtime or dispatches config commands
- `index.json`: display metadata for frontend rendering
- `_template/index.yaml`: Kubernetes deployment manifest

This image is now opinionated for gateway usage: the default startup path is fixed to `hermes gateway`.

Run interactive CLI:

```bash
docker run --rm -it \
  -v $(pwd)/.hermes:/home/agent/.hermes \
  agent-hub/hermes:dev
```

Check version:

```bash
docker run --rm agent-hub/hermes:dev version
```

Open a shell inside the image:

```bash
docker run --rm -it agent-hub/hermes:dev shell
```

Run the gateway explicitly:

```bash
docker run --rm agent-hub/hermes:dev gateway run
```

Example config command:

```bash
docker run --rm -it agent-hub/hermes:dev config set config http://xxx.xxx.xxx/v1 sk-xxxxxxxxxx gpt-5.4
```

The pinned Hermes source ref for this image is `v2026.4.16`.

Container startup behavior:

- image `ENTRYPOINT` is `["/init", "/opt/agent/entrypoint.sh"]`
- image `CMD` is `["gateway"]`
- API server defaults baked into the image are:
  - `API_SERVER_ENABLED=true`
  - `API_SERVER_HOST=0.0.0.0`
  - `API_SERVER_PORT=8642`
  - `API_SERVER_KEY=change-me-local-dev`
- in Kubernetes, pass Hermes CLI arguments through `args`, for example `["gateway"]` or `["gateway", "--help"]`
