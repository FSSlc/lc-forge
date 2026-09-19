#!/bin/bash
# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* ./build-aux
set -eu

autoreconf --install --symlink

./configure \
    --prefix="$PREFIX" \
    --enable-static=no \
    --enable-shared=yes \
    --verbose

make V=1
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR:-}" != "" ]]; then
make check || { cat ./test-suite.log && false; }
fi
