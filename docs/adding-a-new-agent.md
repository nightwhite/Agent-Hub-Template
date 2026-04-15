# adding a new agent

## 1. scaffold from template

```bash
make new-agent AGENT=my-agent
```

This copies `agents/_template` to `agents/my-agent` and appends a disabled registry entry.

## 2. update metadata

Edit `agents/my-agent/agent.yaml`.

At minimum, set:

- `name`
- `version`
- `base`
- `image.repository`
- `source.repository`
- `source.ref`
- `metadata.description`

## 3. implement the real runtime

Update:

- `agents/my-agent/Dockerfile`
- `agents/my-agent/install.sh`
- `agents/my-agent/entrypoint.sh`
- `agents/my-agent/healthcheck.sh`
- `agents/my-agent/tests/smoke.sh`

Rules:

- install the real agent runtime or CLI
- do not ship a fake demo process as the agent
- keep shared logic in `shared/`, not copied across agents

## 4. build and test locally

```bash
make build-agent AGENT=my-agent
make test-agent AGENT=my-agent
```

## 5. enable the agent in the registry

After local build and smoke test succeed, edit `registry/agents.yaml` and change the new entry to:

```yaml
enabled: true
```

## 6. verify repository-level checks

```bash
make validate
make build-all
make test-all
```

## 7. open a pull request

The recommended CI sequence is:

1. validate workflow
2. build workflow
3. release workflow after tagging or manual dispatch
