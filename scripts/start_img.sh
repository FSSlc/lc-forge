#!/bin/bash
set -Eeuo pipefail

# shellcheck disable=SC1091 # common.sh is sourced via a runtime-computed path
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cd "$REPO_ROOT" || exit 1

IMAGE_REPO="${IMAGE_REPO:-ghcr.io/fsslc/pixi}"
CONTAINER_NAME="${CONTAINER_NAME:-pixi}"

usage() {
  echo "Usage: $0 [-f|--force] [--run <command>] [tag]"
  echo "  -f, --force        Remove an existing container before starting"
  echo "  --run <command>    Non-interactive: ensure container is up, then"
  echo "                     docker exec the given shell command inside it"
  echo "  -h, --help         Show this help"
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

container_running() {
  docker ps --filter "name=^/${CONTAINER_NAME}$" --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"
}

container_status() {
  docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format '{{.Status}}' | head -n 1
}

# Detached long-lived container used for subsequent docker exec calls.
start_detached_container() {
  local tag="$1"

  docker run -d --name "$CONTAINER_NAME" \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -v "$REPO_ROOT":"$REPO_ROOT" -w "$REPO_ROOT" \
    "${IMAGE_REPO}:${tag}" \
    sleep infinity
}

run_interactive_container() {
  local tag="$1"

  docker run -ti --name "$CONTAINER_NAME" \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -v "$REPO_ROOT":"$REPO_ROOT" -w "$REPO_ROOT" \
    "${IMAGE_REPO}:${tag}"
}

# Ensure a named container is running (create or start as needed).
ensure_container() {
  local tag="$1"

  if container_running; then
    return 0
  fi

  if container_exists; then
    if docker start "$CONTAINER_NAME" >/dev/null 2>&1; then
      return 0
    fi
    echo "Failed to start existing container ($(container_status)); removing and recreating." >&2
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || {
      echo "Failed to remove stale container. Try: docker rm -f $CONTAINER_NAME" >&2
      return 1
    }
  fi

  start_detached_container "$tag"
}

force=0
img_tag=""
run_cmd=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      force=1
      shift
      ;;
    --run)
      if [[ $# -lt 2 ]]; then
        echo "Option --run requires a command argument" >&2
        usage
      fi
      run_cmd="$2"
      shift 2
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

# Non-interactive CI/local path: ensure container, then exec a command.
if [[ -n "$run_cmd" ]]; then
  if [[ "$force" -eq 1 ]]; then
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  fi
  ensure_container "$img_tag"
  exec docker exec \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -w "$REPO_ROOT" \
    "$CONTAINER_NAME" \
    bash -lc "$run_cmd"
fi

if [[ "$force" -eq 1 ]]; then
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  run_interactive_container "$img_tag"
elif ! container_exists; then
  run_interactive_container "$img_tag"
else
  if [[ "$(container_status)" == Exited* ]]; then
    if docker start "$CONTAINER_NAME" >/dev/null 2>&1; then
      docker exec -ti "$CONTAINER_NAME" bash
      exit $?
    fi
    echo "Failed to start existing container ($(container_status)); removing stale container and recreating." >&2
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || {
      echo "Failed to remove stale container. Try: docker rm -f $CONTAINER_NAME" >&2
      exit 1
    }
    run_interactive_container "$img_tag"
    exit $?
  fi
  docker exec -ti "$CONTAINER_NAME" bash
fi
