#!/bin/bash
set -Eeuo pipefail

# shellcheck disable=SC1091 # common.sh is sourced via a runtime-computed path
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cd "$REPO_ROOT" || exit 1

usage() {
  echo "Usage: $0 -r <recipe_dir>"
  echo "  -r <recipe_dir>  Convert meta.yaml to recipe.yaml in the given recipe directory"
  echo "  -h               Show this help"
  exit "${1:-1}"
}

recipe_dir=""

while getopts ":r:h" opt; do
  case $opt in
    r) recipe_dir="$OPTARG" ;;
    h) usage 0 ;;
    :)
      echo "Option -$OPTARG requires an argument" >&2
      usage
      ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

if [[ -z "$recipe_dir" ]]; then
  usage
fi

recipe_dir="$(resolve_recipe_dir "$recipe_dir")"
meta_file="$recipe_dir/meta.yaml"
recipe_file="$recipe_dir/recipe.yaml"

crm_convert "$meta_file" "$recipe_file"
