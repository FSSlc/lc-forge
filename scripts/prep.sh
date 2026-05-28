#!/bin/bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PACKAGE_NAME_PATTERN='^[A-Za-z0-9_.-]+$'

usage() {
  echo "Usage: $0 <package_name>"
  exit 1
}

pkgname="${1:-}"

if [[ -z "$pkgname" ]]; then
  usage
fi

if [[ ! "$pkgname" =~ $PACKAGE_NAME_PATTERN ]]; then
  echo "Invalid package name: $pkgname" >&2
  echo "Package names may contain only letters, numbers, dots, underscores, and hyphens." >&2
  exit 1
fi

feedstock_dir="${pkgname}-feedstock"
todo_recipe_dir="$REPO_ROOT/todo/$pkgname"
refers_dir="$REPO_ROOT/../refers"
refers_feedstock_dir="$refers_dir/$feedstock_dir"

git clone "https://github.com/conda-forge/${feedstock_dir}.git"

rm -rf -- "$todo_recipe_dir"
mkdir -p "$REPO_ROOT/todo"
cp -R "$feedstock_dir/recipe" "$todo_recipe_dir"

if [[ -f "$todo_recipe_dir/meta.yaml" ]]; then
  tmp_recipe="$(mktemp "$todo_recipe_dir/recipe.yaml.tmp.XXXXXX")"
  cleanup_recipe_tmp() {
    rm -f "$tmp_recipe"
  }
  trap cleanup_recipe_tmp EXIT
  crm convert "$todo_recipe_dir/meta.yaml" > "$tmp_recipe"
  mv "$tmp_recipe" "$todo_recipe_dir/recipe.yaml"
  trap - EXIT
fi

mkdir -p "$refers_dir"
if [[ -d "$refers_feedstock_dir" ]]; then
  rm -rf -- "$refers_feedstock_dir"
fi
mv "$feedstock_dir" "$refers_dir"
