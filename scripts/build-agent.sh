#!/usr/bin/env bash
set -euo pipefail

AGENT="${1:-hermes}"
META_FILE="agents/${AGENT}/agent.yaml"
DOCKERFILE="agents/${AGENT}/Dockerfile"

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "Agent Dockerfile not found: $DOCKERFILE" >&2
  exit 1
fi

if [[ ! -f "$META_FILE" ]]; then
  echo "Agent metadata not found: $META_FILE" >&2
  exit 1
fi

BASE_NAME="$(awk '/^base:/{print $2; exit}' "$META_FILE")"
META_REPOSITORY="$(awk '/repository:/{print $2; exit}' "$META_FILE")"
DEFAULT_TAG="$(awk '/tag:/{print $2; exit}' "$META_FILE")"
BASE_META_FILE="base/${BASE_NAME}/base.yaml"
BASE_META_REPOSITORY="$(awk '/repository:/{print $2; exit}' "$BASE_META_FILE")"
BASE_DEFAULT_TAG="$(awk '/tag:/{print $2; exit}' "$BASE_META_FILE")"
BASE_REPOSITORY="${BASE_REGISTRY_OVERRIDE:-${REGISTRY_OVERRIDE_BASE:-$BASE_META_REPOSITORY}}"
REPOSITORY="${AGENT_REGISTRY_OVERRIDE:-${REGISTRY_OVERRIDE:-$META_REPOSITORY}}"
BASE_IMAGE="${BASE_IMAGE:-${BASE_REPOSITORY}:${BASE_TAG:-$BASE_DEFAULT_TAG}}"
IMAGE="${REPOSITORY}:${AGENT_TAG:-$DEFAULT_TAG}"

echo "==> Building agent image: $IMAGE"
echo "    using base image: $BASE_IMAGE"
docker build \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --file "$DOCKERFILE" \
  --tag "$IMAGE" \
  .
