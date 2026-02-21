#!/usr/bin/env bash

sed -i -e 's,"glx.h",<GL/glx.h>,' server/*.[hc]*

mkdir -p build
cd build
cmake \
    -DTJPEG_INCLUDE_DIR=$PREFIX/include \
    -DTJPEG_LIBRARY=$PREFIX/lib/libturbojpeg.so \
    -DVGL_BUILDSTATIC=1 \
    -DVGL_FAKEOPENCL=1 \
    -DVGL_FAKEXCB=1 \
    -DVGL_FORCEINLINE=1 \
    -DVGL_SYSTEMFLTK=0 \
    -DVGL_USEHELGRIND=0 \
    -DVGL_USEIFR=0 \
    -DVGL_USESSL=1 \
    -DVGL_USEXV=0 \
    -DLIBX11_18=0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib/VirtualGL/ \
    -DCMAKE_INSTALL_BINDIR=$PREFIX/bin \
    -DCMAKE_INSTALL_INCLUDEDIR=$PREFIX/include \
    -DCMAKE_EXE_LINKER_FLAGS="${CMAKE_EXE_LINKER_FLAGS} -L ${BUILD_PREFIX}/${HOST}/sysroot/usr/lib64 -L ${BUILD_PREFIX}/${HOST}/sysroot/usr/lib" \
    -DCMAKE_SHARED_LINKER_FLAGS="${CMAKE_SHARED_LINKER_FLAGS} -L ${BUILD_PREFIX}/${HOST}/sysroot/usr/lib64 -L ${BUILD_PREFIX}/${HOST}/sysroot/usr/lib" \
    ..

make -j${CPU_COUNT} install
mkdir -p $PREFIX/libexec
mv $PREFIX/bin/.vglrun.vars64 $PREFIX/libexec/vglrun.vars64
