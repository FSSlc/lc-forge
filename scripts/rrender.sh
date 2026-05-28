#!/bin/bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

DEFAULT_CHANNEL="https://prefix.dev/scns"

usage() {
  echo "Usage: $0 <recipe_dir>"
  exit 1
}

recipe_dir="${1:-}"

if [[ -z "$recipe_dir" ]]; then
  usage
fi

rattler-build build --skip-existing=all --experimental \
  -m conda_build_config.yaml -c "$DEFAULT_CHANNEL" \
  --render-only -r "$recipe_dir"
