#!/usr/bin/env bash

export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$BUILD_PREFIX/lib/pkgconfig:$BUILD_PREFIX/lib64/pkgconfig
./autogen.sh --datarootdir=$PREFIX/share --prefix=$PREFIX
make -j${CPU_COUNT} install
