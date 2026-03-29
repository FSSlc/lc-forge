#!/bin/bash

set -e

DISABLES="--disable-cairo --disable-opencl --disable-cuda --disable-nvml"
DISABLES="$DISABLES --disable-gl --disable-libudev"

chmod +x configure

case "$target_platform" in
    osx-*)
        autoreconf -ivf
        ./configure --prefix=$PREFIX $DISABLES || (cat config.log; false)
        ;;
    linux-*)
        autoreconf -ivf
        export LDFLAGS="${LDFLAGS} -Wl,--as-needed"
        ./configure --prefix=$PREFIX $DISABLES
        ;;
    win-*)
        export LDFLAGS="$LDFLAGS $PREFIX/lib/pthreads.lib"
        export CPPFLAGS="$CPPFLAGS -Dputenv=_putenv -Dmktemp=_mktemp -Dopen=_open -Dunlink=_unlink -Dclose=_close -Dstrdup=_strdup"
        export HWLOC_LDFLAGS="-no-undefined"
        # Skip failing tests that are skipped on Linux x86_64 and OSX, but not skipped on windows
        sed -i "s|SUBDIRS += x86||g" tests/hwloc/Makefile.am
        sed -i "s|-Xlinker --output-def -Xlinker .libs/libhwloc.def||g" hwloc/Makefile.am
        autoreconf -ivf
        chmod +x configure
        ./configure --prefix="$PREFIX" --libdir="$PREFIX/lib" $DISABLES || (cat config.log; false)
        patch_libtool
        make V=1
        ;;
esac

make -j${CPU_COUNT} V=1
if [[ "${CONDA_BUILD_CROSS_COMPILATION}" != "1" ]]; then
  make check -j${CPU_COUNT} V=1 -k
fi
make install V=1
