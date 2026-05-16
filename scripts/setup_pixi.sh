#!/bin/bash

curl -fsSL https://pixi.sh/install.sh | sh
source ~/.bashrc

pixi  global install -e tools conda-build rattler-build conda-recipe-manager
