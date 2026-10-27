#!/usr/bin/env bash
# cp $BUILD_PREFIX/share/libtool/build-aux/config.* ./build-aux

set -e -o pipefail -x

if [[ $CONDA_BUILD_CROSS_COMPILATION == 1 && $target_platform == osx-arm64 ]]; then
	# Get an updated config.sub and config.guess
	cp -v $BUILD_PREFIX/share/gnuconfig/config.* ./build-aux
	cp src/syscfg/lock-obj-pub.aarch64-apple-darwin.h src/syscfg/lock-obj-pub.darwin20.0.0.h
fi

autoreconf -if
./configure --prefix=$PREFIX

make
make install

if [[ $CONDA_BUILD_CROSS_COMPILATION != 1 && $target_platform != osx-arm64 ]]; then
	make -v -v -v check
fi