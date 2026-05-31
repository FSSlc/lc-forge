#!/bin/sh
set -ex

mkdir -p out/release
cd out/release
cmake ${CMAKE_ARGS}\
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$PREFIX \
  -DMI_INSTALL_TOPLEVEL=ON \
  -DMI_BUILD_TESTS=OFF \
  -DMI_BUILD_SHARED=ON \
  -DMI_BUILD_STATIC=OFF \
  -DMI_BUILD_OBJECT=OFF \
  -DMI_OVERRIDE=OFF \
  -DMI_LOCAL_DYNAMIC_TLS=ON \
  ../..

ninja install
