# agent-hub-template

`agent-hub-template` is an Agent Image Factory repository template.

It is designed for teams that need to build and maintain multiple standardized agent container images from one or more reusable base images, with GitHub Actions as the primary execution path.

This repository is intentionally organized as a build platform template instead of a pile of unrelated Dockerfiles.

## What this repository is for

- Build and maintain one or more reusable base images.
- Define each agent in an isolated directory under `agents/`.
- Build agent images on top of a selected base image.
- Reuse shared scripts, entrypoints, metadata parsing, and validation logic.
- Drive local builds and GitHub Actions from the same registry metadata.
- Add new agents with minimal changes to shared infrastructure.

## Repository structure

```text
base/       reusable base image definitions
agents/     per-agent image definitions and tests
shared/     reusable shell helpers and entrypoint logic
scripts/    build, validate, scaffold, test, and release commands
registry/   registry-style metadata for enabled bases and agents
docs/       architecture and authoring guidance
.github/    GitHub Actions workflows
```

## Current implementation

- Base image: `ubuntu`
- Real agent image: `hermes`
- New agent scaffold: `agents/_template`

## Design principles

1. Base images and agent images are decoupled.
2. Each agent lives in its own directory.
3. Shared logic is centralized in `shared/` and `scripts/`.
4. Registry metadata drives builds instead of directory guessing.
5. GitHub Actions stays thin and delegates to repository scripts.
6. New agents should start from `_template`, not from copy-paste drift.

## Quick start

Validate the repository:

```bash
make validate
```

Build the base image:

```bash
make build-base BASE=ubuntu
```

Build the real Hermes image:

```bash
make build-agent AGENT=hermes
```

Run the Hermes CLI with a persisted Hermes home directory:

```bash
docker run --rm -it -v $(pwd)/.hermes:/home/agent/.hermes agent-hub/hermes:dev
```

Check Hermes version from the image:

```bash
docker run --rm agent-hub/hermes:dev version
```

Open a shell instead:

```bash
docker run --rm -it agent-hub/hermes:dev shell
```

Run the agent smoke test:

```bash
make test-agent AGENT=hermes
```

## Default image names

- Base image: `agent-hub/base-ubuntu:dev`
- Hermes image: `agent-hub/hermes:dev`

These defaults can be overridden for CI/release flows through environment variables and workflow configuration.

## How to add a new agent

Scaffold a new agent from the template:

```bash
make new-agent AGENT=my-agent
```

Then update the generated files:

- `agents/my-agent/agent.yaml`
- `agents/my-agent/Dockerfile`
- `agents/my-agent/install.sh`
- `agents/my-agent/entrypoint.sh`
- `agents/my-agent/healthcheck.sh`
- `agents/my-agent/tests/smoke.sh`

Build and test it locally:

```bash
make build-agent AGENT=my-agent
make test-agent AGENT=my-agent
```

Enable it in CI only after the image builds and the smoke test passes.

Additional guidance: `docs/adding-a-new-agent.md`

## Registry-driven build model

The repository uses registry-style metadata files to describe buildable objects.

- `registry/bases.yaml` declares supported base images.
- `registry/agents.yaml` declares supported agent images.

This keeps build and release automation deterministic and prevents GitHub Actions from inferring build targets by scanning directories.

## GitHub Actions model

Recommended workflow split:

- `validate.yml`: registry validation, shell checks, and lightweight repo checks
- `build.yml`: matrix build for bases and agents on push / pull request
- `release.yml`: authenticated publish flow for tagged releases or manual dispatch

Workflows should call `scripts/*.sh` instead of embedding complex shell logic in YAML.

## Template contract for new agents

Every agent directory should contain at least:

```text
agent.yaml       agent metadata and base selection
Dockerfile       final image assembly
install.sh       agent-specific installation logic
entrypoint.sh    runtime entrypoint
healthcheck.sh   image health probe
tests/smoke.sh   minimal runtime verification
README.md        per-agent notes
```

## Environment variables

See `.env.example` for overridable defaults such as image repository, namespace, and tag strategy.

## Suggested next steps after creating the repo

1. Push the repository to GitHub.
2. Enable GitHub Actions.
3. Set up GHCR permissions for release workflows.
4. Verify `validate`, `build`, and `release` workflows on a branch.
5. Add the next real agent image from `agents/_template`.
