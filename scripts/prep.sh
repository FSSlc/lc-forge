#!/bin/bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

pkgname=$1

if [ -z "$pkgname" ]; then
  echo "Usage: $0 <package-name>"
  exit 1
fi

git clone https://github.com/conda-forge/${pkgname}-feedstock.git
cp -r ${pkgname}-feedstock/recipe ./todo/${pkgname}
if [ -f ./todo/${pkgname}/meta.yaml ]; then
  crm convert ./todo/${pkgname}/meta.yaml > ./todo/${pkgname}/recipe.yaml
fi
mv ${pkgname}-feedstock ../refers
