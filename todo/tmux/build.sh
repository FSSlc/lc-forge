#!/bin/bash

set -exvo pipefail

autoreconf -f -i

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* ./etc

if [[ ${target_platform} =~ linux.* ]]; then
  ./configure --prefix=$PREFIX --enable-sixel
else
  ./configure --prefix=$PREFIX --enable-sixel --enable-utf8proc
fi

make
make install
