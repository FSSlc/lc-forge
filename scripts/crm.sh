#!/bin/bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

usage() {
  echo "Usage: $0 <recipe_dir>"
  exit 1
}

recipe_dir="${1:-}"

if [[ -z "$recipe_dir" ]]; then
  usage
fi

meta_file="$REPO_ROOT/$recipe_dir/meta.yaml"
recipe_file="$REPO_ROOT/$recipe_dir/recipe.yaml"
tmp_file="$(mktemp "$REPO_ROOT/$recipe_dir/recipe.yaml.tmp.XXXXXX")"

cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

if [[ ! -f "$meta_file" ]]; then
  echo "Missing meta.yaml: $meta_file" >&2
  exit 1
fi

crm convert "$meta_file" > "$tmp_file"
mv "$tmp_file" "$recipe_file"
trap - EXIT
