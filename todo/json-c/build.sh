#!/bin/bash
# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* .

# https://github.com/json-c/json-c/issues/406
export CPPFLAGS="${CPPFLAGS/-DNDEBUG/}"

mkdir build
cd build
cmake $CMAKE_ARGS ..

make ${VERBOSE_AT}
if [[ "${CONDA_BUILD_CROSS_COMPILATION}" != "1" ]]; then
    make test ${VERBOSE_AT}
fi
make install

# We can remove this when we start using the new conda-build.
find $PREFIX -name '*.la' -delete
