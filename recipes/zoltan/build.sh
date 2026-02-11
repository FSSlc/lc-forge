#!/bin/bash

set -ex

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* config/

mkdir build; cd $_

export LDFLAGS="-L$PREFIX/lib -lmpi $LDFLAGS"

../configure --prefix=$PREFIX --srcdir=$SRC_DIR

make -j${CPU_COUNT}

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR}" != "" ]]; then
    make test
fi

make install
