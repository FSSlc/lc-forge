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

mkdir -p "$refers_dir"
if [[ -d "$refers_feedstock_dir" ]]; then
  rm -rf -- "$refers_feedstock_dir"
fi

pushd "$refers_dir" > /dev/null || exit 1
git clone "https://github.com/conda-forge/${feedstock_dir}.git"
popd > /dev/null || exit 1

rm -rf -- "$todo_recipe_dir"
mkdir -p "$REPO_ROOT/todo"
cp -R "$refers_dir"/"$feedstock_dir/recipe" "$todo_recipe_dir"

stderr_file="$(mktemp)"
cleanup() {
  rm -f "$stderr_file"
}
trap cleanup EXIT

crm convert "$todo_recipe_dir/meta.yaml" > "$todo_recipe_dir/recipe.yaml" 2> "$stderr_file" || true

if [[ -s "$stderr_file" ]]; then
  if ! grep -q '0 errors' "$stderr_file"; then
    echo "Failed to convert meta.yaml to recipe.yaml"
    echo "add ${pkgname} to only-meta.txt"
    echo "${pkgname}" >> only-meta.txt
    awk 'NF{print} END{print ""}' only-meta.txt > tmp && mv tmp only-meta.txt
  fi
fi
