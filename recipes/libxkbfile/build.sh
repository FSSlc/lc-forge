#!/usr/bin/env bash
set -ex

# Get an updated config.sub and config.guess
chmod +w ./config.guess ./config.sub
cp $BUILD_PREFIX/share/gnuconfig/config.* ./

autoreconf -ivf

./configure --prefix=$PREFIX
make
make install
make check
