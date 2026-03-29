#!/bin/bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

curl -fsSL https://pixi.sh/install.sh | sh

echo 'eval "$(pixi completion --shell bash)"' >> ~/.bashrc

source ~/.bashrc

$HOME/.pixi/bin/pixi global install -e tools \
    rattler-build conda-recipe-manager rattler-index conda conda-build
