#!/bin/bash
set -Eeuo pipefail

# shellcheck disable=SC1091 # common.sh is sourced via a runtime-computed path
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cd "$REPO_ROOT" || exit 1

PACKAGE_NAME_PATTERN='^[A-Za-z0-9_.-]+$'

usage() {
  echo "Usage: $0 <package_name>"
  echo "  Clone conda-forge feedstock and copy recipe into todo/<package_name>."
  echo "  -h  Show this help"
  exit "${1:-1}"
}

case "${1:-}" in
  -h|--help) usage 0 ;;
esac

pkgname="${1:-}"

if [[ -z "$pkgname" ]]; then
  usage
fi

if [[ ! "$pkgname" =~ $PACKAGE_NAME_PATTERN ]]; then
  echo "Invalid package name: $pkgname" >&2
  echo "Package names may contain only letters, numbers, dots, underscores, and hyphens." >&2
  exit 1
fi

require_cmd git

feedstock_dir="${pkgname}-feedstock"
todo_recipe_dir="$REPO_ROOT/todo/$pkgname"
refers_dir="$REPO_ROOT/../refers"
refers_feedstock_dir="$refers_dir/$feedstock_dir"

mkdir -p "$refers_dir"
if [[ -d "$refers_feedstock_dir" ]]; then
  rm -rf -- "$refers_feedstock_dir"
fi

git clone "https://github.com/conda-forge/${feedstock_dir}.git" "$refers_feedstock_dir"

if [[ ! -d "$refers_feedstock_dir/recipe" ]]; then
  echo "Feedstock has no recipe/ directory: $refers_feedstock_dir" >&2
  exit 1
fi

rm -rf -- "$todo_recipe_dir"
mkdir -p "$REPO_ROOT/todo"
cp -R "$refers_feedstock_dir/recipe" "$todo_recipe_dir"

if [[ ! -f "$todo_recipe_dir/recipe.yaml" ]]; then
  if [[ ! -f "$todo_recipe_dir/meta.yaml" ]]; then
    echo "Neither recipe.yaml nor meta.yaml found in $todo_recipe_dir" >&2
    exit 1
  fi

  if ! crm_convert "$todo_recipe_dir/meta.yaml" "$todo_recipe_dir/recipe.yaml"; then
    echo "Failed to convert meta.yaml to recipe.yaml" >&2
    echo "add ${pkgname} to only-meta.txt" >&2
    only_meta="$REPO_ROOT/only-meta.txt"
    touch "$only_meta"
    if ! grep -Fxq "$pkgname" "$only_meta"; then
      printf '%s\n' "$pkgname" >>"$only_meta"
    fi
    rm -f "$todo_recipe_dir/recipe.yaml"
  fi
fi
