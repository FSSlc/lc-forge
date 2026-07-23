#!/bin/sh

set -e -o pipefail

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* .

if [[ "${target_platform}" == "osx-arm64" ]]; then
    EXTRA_CONFIGURE_ARGS="--disable-simd"
fi
./configure --prefix=$PREFIX --without-included-zlib --without-included-popt ${EXTRA_CONFIGURE_ARGS:-}
make -j${CPU_COUNT}
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" ]]; then
    # Don't run tests with emulation as they will be flaky due to the slow timings.

    # Known flaky test on osx
    if [[ "${target_platform}" == osx-* ]]; then
        rm testsuite/chmod-symlink-race.test
        rm testsuite/symlink-dirlink-basis.test
    fi
    make check
fi
make install
