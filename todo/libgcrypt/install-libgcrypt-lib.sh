#!/usr/bin/env bash

set -euo pipefail

mkdir -p $PREFIX/lib
if [[ "${target_platform}" == osx-* ]]; then
    cp ./src/.libs/libgcrypt.*.dylib $PREFIX/lib
else
    cp ./src/.libs/libgcrypt.so.* $PREFIX/lib
fi

mkdir -p $PREFIX/lib/pkgconfig
cp ./src/libgcrypt.pc $PREFIX/lib/pkgconfig
