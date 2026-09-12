#!/bin/bash

mkdir build && cd build

cmake -GNinja ${CMAKE_ARGS} \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_INCLUDEDIR=include \
    -DENABLE_COMMONCRYPTO=OFF \
    -DENABLE_GNUTLS=OFF \
    -DENABLE_MBEDTLS=OFF \
    -DENABLE_OPENSSL=ON \
    -DENABLE_WINDOWS_CRYPTO=OFF \
    -DENABLE_BZIP2=ON \
    -DENABLE_LZMA=OFF \
    -DENABLE_ZSTD=OFF \
    ..
ninja
if [[ "${CONDA_BUILD_CROSS_COMPILATION}" != "1" ]]; then
ninja test
fi
ninja install
