#!/bin/bash

cmake -B build \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=ON \
    -DYYJSON_BUILD_TESTS=OFF \
    -DYYJSON_BUILD_MISC=OFF \
    ${CMAKE_ARGS}

ninja -C build install
