#!/bin/bash

set -ex

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* .

./configure \
    --prefix="${PREFIX}" \
    --enable-color       \
    --enable-nanorc      \
    --enable-multibuffer

make
make check
make install
