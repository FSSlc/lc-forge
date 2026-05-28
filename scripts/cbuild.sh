#!/bin/bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

DEFAULT_CHANNEL="https://prefix.dev/scns"
OUTPUT_DIR="$REPO_ROOT/output"

usage() {
  echo "Usage: $0 -r <recipe_dir> [-f]"
  echo "  -r <recipe_dir>  Specify the recipe directory (required)"
  echo "  -f               Force rebuild existing packages (optional, default: skip existing)"
  exit 1
}

fix_output_owner() {
  if [[ ! -d "$OUTPUT_DIR" || "${EUID:-$(id -u)}" -ne 0 ]]; then
    return 0
  fi

  chown -R "${HOST_UID:-1000}:${HOST_GID:-1000}" "$OUTPUT_DIR"
}

recipe_dir=""
skip_existing=true

while getopts "r:f" opt; do
  case $opt in
    r) recipe_dir="$OPTARG" ;;
    f) skip_existing=false ;;
    *) usage ;;
  esac
done

if [[ -z "$recipe_dir" ]]; then
  usage
fi

mkdir -p "$OUTPUT_DIR"

cmd=(
  conda build
  --croot "$OUTPUT_DIR"
  -m conda_build_config.yaml
  -c "$DEFAULT_CHANNEL"
  "$recipe_dir"
)

if $skip_existing; then
  cmd+=(--skip-existing)
fi

build_status=0
"${cmd[@]}" || build_status=$?

fix_output_owner || {
  chown_status=$?
  if [[ "$build_status" -eq 0 ]]; then
    exit "$chown_status"
  fi
  printf 'Warning: failed to fix output ownership after failed build\n' >&2
}

exit "$build_status"
