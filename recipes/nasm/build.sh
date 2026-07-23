#!/bin/bash

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* autoconf/helpers/

./configure --prefix="${PREFIX}"
make
make install
