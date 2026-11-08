#!/bin/bash
set -Eeuo pipefail

# shellcheck disable=SC1091 # common.sh is sourced via a runtime-computed path
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cd "$REPO_ROOT" || exit 1

usage() {
  echo "Usage: $0 -r <recipe_dir> [-f] [-c <channel>]... [--] [extra rattler-build args...]"
  echo "  -r <recipe_dir>  Specify the recipe directory (required). Without its own"
  echo "                   recipe.yaml, every nested recipe is built via --recipe-dir."
  echo "  -f               Force rebuild existing packages (optional, default: skip existing)"
  echo "  -c <channel>     Add an additional -c channel; can be specified multiple times"
  echo "  -h               Show this help"
  echo
  echo "Environment:"
  echo "  DEFAULT_CHANNEL  Default channel (default: https://prefix.dev/scns)"
  echo "  EXTRA_CHANNELS   Extra channels, space- and/or comma-separated"
  echo "  OUTPUT_DIR       Build output root (default: <repo>/output)"
  echo
  echo "Recipe file:"
  echo "  <recipe_dir>/args.txt  Optional. [env] NAME=VALUE sets extra env vars;"
  echo "                         [args] lines add one extra arg each."
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
load_recipe_args "$recipe_dir"

# `<recipe_dir>/recipe.yaml` means one recipe and rattler-build's -r handles it.
# A directory like todo/ has no recipe.yaml of its own but may hold any number of
# nested recipes; -r would look for todo/recipe.yaml and fail, so hand the whole
# directory to --recipe-dir and let rattler-build build every recipe inside it.
recipe_args=(-r "$recipe_dir")
if [[ ! -f "$recipe_dir/recipe.yaml" ]]; then
  nested=$(find "$recipe_dir" -mindepth 2 -name recipe.yaml -print | wc -l)
  if ((nested > 0)); then
    echo "No recipe.yaml in $recipe_dir; building all $((nested)) nested recipe(s)" >&2
    recipe_args=(--recipe-dir "$recipe_dir")
  fi
fi

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
  "${recipe_args[@]}"
)

if $skip_existing; then
  cmd+=(--skip-existing=all)
fi

if [[ ${#RECIPE_EXTRA_ARGS[@]} -gt 0 ]]; then
  cmd+=("${RECIPE_EXTRA_ARGS[@]}")
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
