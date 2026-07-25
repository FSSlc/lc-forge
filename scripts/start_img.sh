#!/bin/bash
set -Eeuo pipefail

# shellcheck disable=SC1091 # common.sh is sourced via a runtime-computed path
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cd "$REPO_ROOT" || exit 1

IMAGE_REPO="${IMAGE_REPO:-ghcr.io/fsslc/pixi}"
CONTAINER_NAME="${CONTAINER_NAME:-pixi}"

usage() {
  echo "Usage: $0 [-f|--force] [tag]"
  echo "  -f, --force   Remove an existing container before starting"
  echo "  -h, --help    Show this help"
  echo
  echo "Environment:"
  echo "  IMAGE_REPO      Container image repo (default: ghcr.io/fsslc/pixi)"
  echo "  CONTAINER_NAME  Container name (default: pixi)"
  echo "  HOST_UID        Host UID for chown in build scripts (auto-set at run)"
  echo "  HOST_GID        Host GID for chown in build scripts (auto-set at run)"
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

  docker run -ti --name "$CONTAINER_NAME" \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -v "$REPO_ROOT":"$REPO_ROOT" -w "$REPO_ROOT" \
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

require_cmd docker

docker pull "${IMAGE_REPO}:${img_tag}"

if [[ "$force" -eq 1 ]]; then
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  run_container "$img_tag"
elif ! container_exists; then
  run_container "$img_tag"
else
  if [[ "$(container_status)" == Exited* ]]; then
    docker start "$CONTAINER_NAME"
  fi
  docker exec -ti "$CONTAINER_NAME" bash
fi
