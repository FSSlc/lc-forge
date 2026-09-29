#!/bin/bash

set -e

DISABLES="--disable-cairo --disable-opencl --disable-cuda --disable-nvml"
DISABLES="$DISABLES --disable-gl --disable-libudev"

chmod +x configure

case "${target_platform:-${TARGET_PLATFORM}}" in
    osx-*)
        autoreconf -ivf
        ./configure --prefix=$PREFIX $DISABLES || (cat config.log; false)
        ;;
    linux-*)
        autoreconf -ivf
        export LDFLAGS="${LDFLAGS} -Wl,--as-needed"
        if [[ ${cuda_compiler_version} != "None" ]]; then
          ./configure --enable-cuda --prefix=$PREFIX --disable-cairo --disable-opencl --disable-gl --disable-libudev
        elif [[ ${ROCM_COMPILATION} == "enabled" ]]; then
          ./configure --prefix=$PREFIX --enable-rsmi $DISABLES
        else
          ./configure --prefix=$PREFIX $DISABLES
        fi
        ;;
    win-*)
        which clang
        export CPPFLAGS="$CPPFLAGS -Dputenv=_putenv -Dmktemp=_mktemp -Dopen=_open -Dunlink=_unlink -Dclose=_close -Dstrdup=_strdup -DO_RDONLY=_O_RDONLY -Dfstat=_fstat -Dstat=_stat -DS_IFREG=_S_IFREG -DS_IFDIR=_S_IFDIR -DS_IFMT=_S_IFMT -DO_RDWR=_O_RDWR -DO_CREAT=_O_CREAT"
        export CFLAGS="$CFLAGS -fms-define-stdc"
        export HWLOC_LDFLAGS="-no-undefined"
        # Skip failing tests that are skipped on Linux x86_64 and OSX, but not skipped on windows
        sed -i "s|SUBDIRS += x86||g" tests/hwloc/Makefile.am
        sed -i "s|-Xlinker --output-def -Xlinker .libs/libhwloc.def||g" hwloc/Makefile.am
        autoreconf -ivf
        chmod +x configure
        ./configure --prefix="$PREFIX" --libdir="$PREFIX/lib" $DISABLES --disable-static || (cat config.log; false)
        patch_libtool
        make V=1
        ;;
esac

make -j${CPU_COUNT} V=1
if [[ "${CONDA_BUILD_CROSS_COMPILATION}" != "1" ]] && [[ ${cuda_compiler_version} == "None" ]]; then
  make check -j${CPU_COUNT} V=1 -k
fi
make install V=1
