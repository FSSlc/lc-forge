#!/bin/bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

usage() {
  echo "Usage: $0 -r <recipe_dir> [-f]"
  echo "  -r <recipe_dir>  Specify the recipe directory (required)"
  echo "  -f               Skip existing packages (optional, default: false)"
  exit 1
}

recipe_dir=""
skip_existing=true

while getopts "r:f" opt; do
  case $opt in
    r) recipe_dir="$OPTARG" ;;
    f) skip_existing=false ;;
    *) usage ;;
  esac
done

if [ -z "$recipe_dir" ]; then
  usage
fi

mkdir -p $REPO_ROOT/output

cmd="conda build --croot $REPO_ROOT/output \
  -m conda_build_config.yaml -c https://prefix.dev/scns \
  $recipe_dir"

if $skip_existing; then
  cmd="$cmd --skip-existing"
fi

$cmd

chown -R 1000:1000 $REPO_ROOT/output
