#!/bin/bash

# 存储脚本所在目录的父目录（仓库根目录）并切换到该目录
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

pkgname=$1

if [ -z "$pkgname" ]; then
  echo "Usage: $0 <package-name>"
  exit 1
fi

git clone https://github.com/conda-forge/${pkgname}-feedstock.git
cp -r ${pkgname}-feedstock/recipe ./recipes/${pkgname}
if [ -f recipes/${pkgname}/meta.yaml ]; then
  crm convert recipes/${pkgname}/meta.yaml > recipes/${pkgname}/recipe.yaml
fi
mv ${pkgname}-feedstock ../refers
