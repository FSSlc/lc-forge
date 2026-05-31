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

if [[ ! -f "$meta_file" ]]; then
  echo "Missing meta.yaml: $meta_file" >&2
  exit 1
fi

stderr_file="$(mktemp)"
cleanup() {
  rm -f "$stderr_file"
}
trap cleanup EXIT

crm convert "$meta_file" > "$recipe_file" 2> "$stderr_file" || true

if [[ -s "$stderr_file" ]]; then
  if ! grep -q '0 errors' "$stderr_file"; then
    cat "$stderr_file" >&2
    exit 1
  fi
fi
