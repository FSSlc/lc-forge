#!/bin/bash
# Get an updated config.sub and config.guess
cp -v $BUILD_PREFIX/share/gnuconfig/config.* .

./configure --prefix=$PREFIX

make
make check
make install
