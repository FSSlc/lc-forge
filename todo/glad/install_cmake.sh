#!/bin/bash
set -ex

mkdir -p $PREFIX/lib/cmake/Glad
cp $SRC_DIR/cmake/GladConfig.cmake $PREFIX/lib/cmake/Glad/GladConfig.cmake
