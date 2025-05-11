#!/bin/bash

mkdir -p build
cd build

cmake \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_FIND_ROOT_PATH=$BUILD_PREFIX \
    -DOPENSSL_INCLUDE_DIR=$BUILD_PREFIX/include \
    -DSSL_SUPPORT=ON \
    -DUSE_OPENSSL=ON \
    ..
make install -j
