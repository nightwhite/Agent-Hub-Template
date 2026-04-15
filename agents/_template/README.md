# change-me agent template

This directory is the scaffold for a new agent image.

After copying it to `agents/<agent-name>/`, update at least:

- `agent.yaml`
- `Dockerfile`
- `install.sh`
- `entrypoint.sh`
- `healthcheck.sh`
- `tests/smoke.sh`

Important:

- Replace the placeholder installation logic with the real upstream agent runtime.
- Do not leave the generated agent enabled in CI until the image builds and the smoke test passes.
- Keep agent-specific logic inside the agent directory. Move only shared logic into `shared/`.
