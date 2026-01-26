#!/bin/bash

export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$BUILD_PREFIX/lib/pkgconfig:$BUILD_PREFIX/lib64/pkgconfig
./configure --prefix=$PREFIX \
    --with-gmp-include=$BUILD_PREFIX/include --with-gmp-lib=$BUILD_PREFIX/lib \
    --with-pbc-include=$BUILD_PREFIX/include/pbc --with-pbc-lib=$BUILD_PREFIX
make install -j
