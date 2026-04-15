#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-agent-hub/change-me:dev}"

docker run --rm "$IMAGE" shell -lc 'test -x /opt/change-me/bin/change-me-run'
