#!/bin/bash
set -Eeuo pipefail

# shellcheck disable=SC1091 # common.sh is sourced via a runtime-computed path
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cd "$REPO_ROOT" || exit 1

usage() {
  echo "Usage: $0 -r <recipe_dir> [-f] [-c <channel>]... [-n <rounds>] [-i] [--] [extra conda-build args...]"
  echo "  -r <recipe_dir>  Specify the recipe directory (required)"
  echo "  -f               Force rebuild existing packages (optional, default: skip existing)"
  echo "  -c <channel>     Add an additional -c channel; can be specified multiple times"
  echo "  -n <rounds>      Build attempts before giving up on AI fixing (default: 3)"
  echo "  -i               Ask before each AI fix round instead of calling AI directly"
  echo "  -h               Show this help"
  echo
  echo "Environment:"
  echo "  DEFAULT_CHANNEL       Default channel (default: https://prefix.dev/scns)"
  echo "  EXTRA_CHANNELS        Extra channels, space- and/or comma-separated"
  echo "  OUTPUT_DIR            Build output root (default: <repo>/output)"
  echo "  AI_MAX_FIX_ROUNDS     Default for -n (default: 3)"
  echo "  AI_API_BASE_URL / AI_API_KEY / AI_MODEL_NAME"
  echo "                        OpenAI-compatible AI endpoint; unset disables AI fixing"
  echo
  echo "Recipe file:"
  echo "  <recipe_dir>/args.txt  Optional. [env] NAME=VALUE sets extra env vars;"
  echo "                         [args] lines add one extra arg each."
  echo
  echo "Logs: <repo>/logs/build-<recipe_dir>-<timestamp>.log (fed to the AI on failure)"
  exit "${1:-1}"
}

recipe_dir=""
skip_existing=true
interactive=false
rounds="${AI_MAX_FIX_ROUNDS:-3}"
extra_cs=()

while getopts ":r:fc:n:ih" opt; do
  case $opt in
    r) recipe_dir="$OPTARG" ;;
    f) skip_existing=false ;;
    c) extra_cs+=("$OPTARG") ;;
    n) rounds="$OPTARG" ;;
    i) interactive=true ;;
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

if ! [[ "$rounds" =~ ^[0-9]+$ ]] || ((rounds < 1)); then
  echo "Error: -n 需要 >= 1 的整数，收到 '$rounds'" >&2
  exit 1
fi

recipe_dir="$(resolve_recipe_dir "$recipe_dir")"
require_cmd conda
mkdir -p "$OUTPUT_DIR"
load_recipe_args "$recipe_dir"

if [[ ${#extra_cs[@]} -gt 0 ]]; then
  build_channel_args "${extra_cs[@]}"
else
  build_channel_args
fi

cmd=(
  conda build
  --croot "$OUTPUT_DIR"
  -m conda_build_config.yaml
  "${CHANNEL_ARGS[@]}"
  "$recipe_dir"
)

if $skip_existing; then
  cmd+=(--skip-existing)
fi

if [[ ${#RECIPE_EXTRA_ARGS[@]} -gt 0 ]]; then
  cmd+=("${RECIPE_EXTRA_ARGS[@]}")
fi

if [[ $# -gt 0 ]]; then
  cmd+=("$@")
fi

build_log="$(make_build_log_path "$(basename "$recipe_dir")")"

BUILD_CMD=("${cmd[@]}")
build_status=0
run_build_with_ai_fix "$recipe_dir" "$build_log" "$interactive" "$rounds" ||
  build_status=$?

fix_output_owner || {
  chown_status=$?
  if [[ "$build_status" -eq 0 ]]; then
    exit "$chown_status"
  fi
  echo "Warning: failed to fix output ownership after failed build" >&2
}

exit "$build_status"
