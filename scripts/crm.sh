#!/bin/bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

recipe_dir=$1

if [ -z "$recipe_dir" ]; then
  echo "Usage: $0 <recipe-dir>"
  exit 1
fi

crm convert $REPO_ROOT/$recipe_dir/meta.yaml > $REPO_ROOT/$recipe_dir/recipe.yaml
