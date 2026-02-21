#!/bin/bash

export CPATH=${PREFIX}/include
export LD_LIBRARY_PATH=${PREFIX}/lib
export PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig

./configure --prefix=${PREFIX} --with-x
make
make install
