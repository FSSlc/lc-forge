#!/bin/bash
set -e
set -x

mkdir -p build
cd build

cmake \
  -DCMAKE_INSTALL_PREFIX=$PREFIX \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
..

make -j $CPU_COUNT

make install
