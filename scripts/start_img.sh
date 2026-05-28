#!/bin/bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

IMAGE_REPO="ghcr.io/fsslc/pixi"
CONTAINER_NAME="pixi"

usage() {
  echo "Usage: $0 [-f|--force] [tag]"
  echo "  -f, --force   Remove an existing pixi container before starting"
  exit "${1:-1}"
}

container_exists() {
  docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"
}

container_status() {
  docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format '{{.Status}}' | head -n 1
}

run_container() {
  local tag="$1"

  docker run -ti --name "$CONTAINER_NAME" -v "$REPO_ROOT":"$REPO_ROOT" -w "$REPO_ROOT" \
    "${IMAGE_REPO}:${tag}"
}

force=0
img_tag=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      force=1
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      if [[ -z "$img_tag" ]]; then
        img_tag="$1"
      else
        echo "Unknown argument: $1" >&2
        usage
      fi
      shift
      ;;
  esac
done

if [[ -z "$img_tag" ]]; then
  img_tag="latest"
fi

docker pull "${IMAGE_REPO}:${img_tag}"

if [[ "$force" -eq 1 ]]; then
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  run_container "$img_tag"
else
  if container_exists; then
    if [[ "$(container_status)" == Exited* ]]; then
      docker start "$CONTAINER_NAME"
    fi
    docker exec -ti "$CONTAINER_NAME" bash
  else
    run_container "$img_tag"
  fi
fi
