#!/usr/bin/env bash

cmake -B build -S . \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_UTILITIES=ON

cmake --build build --config Release --target install -- -j${CPU_COUNT}
cd build && ctest -V -C Release
