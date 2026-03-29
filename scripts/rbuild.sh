#!/bin/bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

recipe_dir=$1

if [ -z "$recipe_dir" ]; then
  echo "Usage: $0 <precipe_dir>"
  exit 1
fi

rattler-build build --skip-existing=all --experimental \
  -m conda_build_config.yaml -c https://prefix.dev/scns \
  -r $recipe_dir

chown -R 1000:1000 $REPO_ROOT/output
