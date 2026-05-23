#!/bin/bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

usage() {
  echo "Usage: $0 -r <recipe_dir> [-f] [-c <channel>]..."
  echo "  -r <recipe_dir>  Specify the recipe directory (required)"
  echo "  -f               Skip existing packages (optional, default: false)"
  echo "  -c <channel>     Add an additional -c channel; can be specified multiple times"
  exit 1
}

recipe_dir=""
skip_existing=true
extra_cs=()

while getopts "r:fc:" opt; do
  case $opt in
    r) recipe_dir="$OPTARG" ;;
    f) skip_existing=false ;;
    c) extra_cs+=("$OPTARG") ;;
    *) usage ;;
  esac
done

if [ -z "$recipe_dir" ]; then
  usage
fi

cmd="rattler-build build --experimental -m conda_build_config.yaml -c https://prefix.dev/scns -r $recipe_dir"

if $skip_existing; then
  cmd="$cmd --skip-existing=all"
fi

# Append any additional -c channels supplied by the user to the end of the command
for ch in "${extra_cs[@]}"; do
  cmd="$cmd -c $ch"
done

$cmd

chown -R 1000:1000 $REPO_ROOT/output
