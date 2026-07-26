#!/bin/bash
set -Eeuo pipefail

# shellcheck disable=SC1091 # common.sh is sourced via a runtime-computed path
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cd "$REPO_ROOT" || exit 1

usage() {
  echo "Usage: $0 -r <recipe_dir> [-f] [-c <channel>]... [--] [extra rattler-build args...]"
  echo "  -r <recipe_dir>  Specify the recipe directory (required)"
  echo "  -f               Force rebuild existing packages (optional, default: skip existing)"
  echo "  -c <channel>     Add an additional -c channel; can be specified multiple times"
  echo "  -h               Show this help"
  echo
  echo "Environment:"
  echo "  DEFAULT_CHANNEL  Default channel (default: https://prefix.dev/scns)"
  echo "  EXTRA_CHANNELS   Extra channels, space- and/or comma-separated"
  echo "  OUTPUT_DIR       Build output root (default: <repo>/output)"
  exit "${1:-1}"
}

recipe_dir=""
skip_existing=true
extra_cs=()

while getopts ":r:fc:h" opt; do
  case $opt in
    r) recipe_dir="$OPTARG" ;;
    f) skip_existing=false ;;
    c) extra_cs+=("$OPTARG") ;;
    h) usage 0 ;;
    :)
      echo "Option -$OPTARG requires an argument" >&2
      usage
      ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
if [[ "${1:-}" == "--" ]]; then
  shift
fi

if [[ -z "$recipe_dir" ]]; then
  usage
fi

recipe_dir="$(resolve_recipe_dir "$recipe_dir")"
require_cmd rattler-build
mkdir -p "$OUTPUT_DIR"

if [[ ${#extra_cs[@]} -gt 0 ]]; then
  build_channel_args "${extra_cs[@]}"
else
  build_channel_args
fi

cmd=(
  rattler-build build
  --experimental
  -m conda_build_config.yaml
  "${CHANNEL_ARGS[@]}"
  -r "$recipe_dir"
)

if $skip_existing; then
  cmd+=(--skip-existing=all)
fi

if [[ $# -gt 0 ]]; then
  cmd+=("$@")
fi

build_status=0
"${cmd[@]}" || build_status=$?

fix_output_owner || {
  chown_status=$?
  if [[ "$build_status" -eq 0 ]]; then
    exit "$chown_status"
  fi
  echo "Warning: failed to fix output ownership after failed build" >&2
}

exit "$build_status"
