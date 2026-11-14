#!/bin/bash
set -ex

cmake $CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=$PREFIX $SRC_DIR
make install
