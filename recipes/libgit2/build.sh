#!/bin/bash

mkdir build && cd build
cmake ${CMAKE_ARGS} .. \
    -GNinja \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_PREFIX_PATH=$PREFIX \
    -DCMAKE_FIND_ROOT_PATH=$PREFIX \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DREGEX_BACKEND=pcre2 \
    -DUSE_SSH=ON \
    -DCMAKE_BUILD_TYPE=Release

ninja install
