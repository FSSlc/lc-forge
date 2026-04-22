#!/bin/bash
set -e -x

# Get meson to find pkg-config when cross compiling
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"

meson setup builddir \
    ${MESON_ARGS} \
    --prefix=$PREFIX \
    -Dasm=enabled \
    -Dx11=enabled \
    -Degl=true \
    -Dglx=enabled \
    -Dgles1=true \
    -Dgles2=true \
    -Dtls=true \
    -Ddispatch-tls=true \
    -Dheaders=true \
    --wrap-mode=nofallback

ninja -v -C builddir
ninja -C builddir install

mv $PREFIX/lib64/lib* $PREFIX/lib/
mv $PREFIX/lib64/pkgconfig/* $PREFIX/lib/pkgconfig/
