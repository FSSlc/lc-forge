#!/bin/bash
set -Eeuo pipefail

# shellcheck disable=SC1091 # common.sh is sourced via a runtime-computed path
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cd "$REPO_ROOT" || exit 1

usage() {
  echo "Usage: $0 -r <recipe_dir> [-c <channel>]... [--] [extra conda-render args...]"
  echo "  -r <recipe_dir>  Specify the recipe directory (required)"
  echo "  -c <channel>     Add an additional -c channel; can be specified multiple times"
  echo "  -h               Show this help"
  echo
  echo "Environment:"
  echo "  DEFAULT_CHANNEL  Default channel (default: https://prefix.dev/scns)"
  echo "  EXTRA_CHANNELS   Extra channels, space- and/or comma-separated"
  exit "${1:-1}"
}

recipe_dir=""
extra_cs=()

while getopts ":r:c:h" opt; do
  case $opt in
    r) recipe_dir="$OPTARG" ;;
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
require_cmd conda

if [[ ${#extra_cs[@]} -gt 0 ]]; then
  build_channel_args "${extra_cs[@]}"
else
  build_channel_args
fi

cmd=(
  conda render
  -m conda_build_config.yaml
  "${CHANNEL_ARGS[@]}"
  "$recipe_dir"
)

if [[ $# -gt 0 ]]; then
  cmd+=("$@")
fi

"${cmd[@]}"
