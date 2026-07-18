#!/bin/bash

set -xe

# Adopt a Unix-friendly path if we're on Windows (see bld.bat).
[ -n "$PATH_OVERRIDE" ] && export PATH="$PATH_OVERRIDE"

LDFLAGS="$LDFLAGS -L$PREFIX/lib"
CFLAGS="$CFLAGS -O3 -I$PREFIX/include"

# The AppVeyor build sets "TARGET_ARCH" to x86 or x64. We need to unset
# this, as TARGET_ARCH is put on the command line by Make via
# its default rules for compiling C files.
export TARGET_ARCH=

# Set `CC` on Windows where it is not set already.
if [ -z "$CC" ]; then
    export CC="gcc"
fi

# Fix some flags on Windows
if [[ ${target_platform} =~ .*win.* ]]; then
   export PKG_CONFIG_PATH="${PREFIX}/Library/lib/pkgconfig"
   LDFLAGS="${LDFLAGS} $(pkg-config --libs zlib)"
   CFLAGS="${CFLAGS} $(pkg-config --cflags zlib)"
   export C_INCLUDE_PATH="${C_INCLUDE_PATH}:$(pkg-config --cflags zlib)"
fi

make -j$CPU_COUNT CC="$CC" LDFLAGS="$LDFLAGS" CFLAGS="$CFLAGS"
if [ "${CONDA_BUILD_CROSS_COMPILATION}" -ne "1" ]; then
    make test
fi

# Use different variable to get "binprefix" on win:
if [ -n "$LIBRARY_BIN" ]; then
    mkdir -p "$LIBRARY_BIN"
    cp pigz unpigz "$LIBRARY_BIN"
else
    mkdir -p "$PREFIX/bin"
    cp pigz unpigz "$PREFIX/bin"
fi
