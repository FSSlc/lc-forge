#! /bin/bash
# Prior to conda-forge, Copyright 2017-2019 Peter Williams and collaborators.
# This file is licensed under a 3-clause BSD license; see LICENSE.txt.

set -ex

if [[ $target_platform == osx* ]] ; then
    meson_config_args=(
        -D docs=false
        -D x11=false
        -D tests=false
    )
else
    meson_config_args=(
        -D docs=false
        -D egl=yes
        -D x11=true
        -D tests=false
        -D libdir=lib
    )
    # hack to prevent x11 from being found by meson and added as pkg-config dep
    # but still have the headers present for successful compilation
    rm -f $PREFIX/lib/pkgconfig/x11.pc
fi

meson setup builddir \
    ${MESON_ARGS} \
    "${meson_config_args[@]}" \
    --prefix=$PREFIX \
    --wrap-mode=nofallback
ninja -v -C builddir -j ${CPU_COUNT}
ninja -C builddir install -j ${CPU_COUNT}

cd $PREFIX
find . '(' -name '*.la' -o -name '*.a' ')' -delete
