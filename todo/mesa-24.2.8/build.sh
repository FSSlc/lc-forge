#!/bin/bash

set -ex

export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$BUILD_PREFIX/lib/pkgconfig
export PKG_CONFIG=$BUILD_PREFIX/bin/pkg-config

meson builddir/ \
  ${MESON_ARGS} \
  --buildtype=release \
  --prefix=$PREFIX \
  -Dplatforms=x11 \
  -Dgallium-drivers=d3d12,swrast \
  -Dplatforms=x11 \
  -Dllvm=true \
  -Dlibdir=lib \
  -Ddri-drivers-path=$PREFIX/opt/mesa/lib/dri \
  -Dgallium-omx=disabled \
  -Dvulkan-drivers=[] \
  -Dosmesa=true \
  || { cat builddir/meson-logs/meson-log.txt; exit 1; }

ninja -C builddir/ -j ${CPU_COUNT}

ninja -C builddir/ install
