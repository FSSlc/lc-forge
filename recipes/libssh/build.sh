#!/bin/bash

set -ex

mkdir build
cd build

cmake ${CMAKE_ARGS} -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${PREFIX} ..
make -j${CPU_COUNT}

make install
