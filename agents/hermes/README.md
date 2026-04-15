# Hermes Agent image

This image installs the real Hermes Agent from the official NousResearch/hermes-agent source repository.

Build:

```bash
make build-agent AGENT=hermes
```

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

Run doctor:

```bash
docker run --rm -it \
  -v $(pwd)/.hermes:/home/agent/.hermes \
  agent-hub/hermes:dev doctor
```

Open a shell inside the image:

```bash
docker run --rm -it agent-hub/hermes:dev shell
```
