#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-ubuntu}"
META_FILE="base/${BASE}/base.yaml"
DOCKERFILE="base/${BASE}/Dockerfile"

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "Base Dockerfile not found: $DOCKERFILE" >&2
  exit 1
fi

if [[ ! -f "$META_FILE" ]]; then
  echo "Base metadata not found: $META_FILE" >&2
  exit 1
fi

META_REPOSITORY="$(awk '/repository:/{print $2; exit}' "$META_FILE")"
DEFAULT_TAG="$(awk '/tag:/{print $2; exit}' "$META_FILE")"
REPOSITORY="${REGISTRY_OVERRIDE:-$META_REPOSITORY}"
IMAGE="${REPOSITORY}:${BASE_TAG:-$DEFAULT_TAG}"

echo "==> Building base image: $IMAGE"
docker build \
  --file "$DOCKERFILE" \
  --tag "$IMAGE" \
  .
