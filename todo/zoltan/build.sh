#!/bin/bash

set -ex

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* config/

mkdir build; cd $_

export LDFLAGS="-L$PREFIX/lib -lmpi $LDFLAGS"

# refer: https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=zoltan
../configure --prefix=$PREFIX --srcdir=$SRC_DIR \
    --enable-mpi --with-mpi-compilers \
    --enable-tests --enable-zoltan-examples \
    --with-gnumake \
    --with-ar='$(CXX) -shared $(LDFLAGS) -o' \
    --with-cflags="-fPIC" \
    --with-cxxflags="-fPIC" \
    --with-ldflags="-L$PREFIX/lib -lmpi -lm" \
    RANLIB=echo
make -j${CPU_COUNT}

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR}" != "" ]]; then
    make test
fi

make install
mv $PREFIX/lib/libzoltan.a $PREFIX/lib/libzoltan.so
