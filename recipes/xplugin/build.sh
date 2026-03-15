#!/bin/bash
set -ex

mkdir -p build
cd build
cmake \
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DXPLUGIN_BUILD_TESTS=ON \
  -DXPLUGIN_BUILD_EXAMPLES=ON \
  -DXPLUGIN_BUILD_DOCS=OFF \
  -DCMAKE_PREFIX_PATH=$BUILD_PREFIX \
  -DCMAKE_INSTALL_PREFIX=$PREFIX \
  ..

# build
ninja

# test
ctest -V -R test
ctest -V -R example

# install
ninja install
