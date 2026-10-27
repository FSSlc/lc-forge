#!/bin/bash

ls *.bz2 >/dev/null 2>&1 && tar -x --strip-components=1 -f *.bz2

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* ./build-aux

if [[ "$(uname -s)" == "Linux" ]]
then
    LDFLAGS="$LDFLAGS -lrt"
fi

./configure --prefix=$PREFIX
make
make install
