#!/bin/bash

export PERL=${BUILD_PREFIX}/bin/perl
export CPATH=$CPATH:${BUILD_PREFIX}/include
export LOCAL_LIB_ROOT=${BUILD_PREFIX}/lib
export LOCAL_INCLUDE=${BUILD_PREFIX}/include
export LOCAL_INSTALL_BIN=${BUILD_PREFIX}/bin
export BISON=${BUILD_PREFIX}/bin/bison

. ./env

make deps
make src
make test

mkdir -p ${PREFIX}/bin ${PREFIX}/lib/openabe ${PREFIX}/include/openabe

cp -r ${BUILD_PREFIX}/include/gmp*.h ${PREFIX}/include/openabe
cp ${BUILD_PREFIX}/lib/libgmp* ${PREFIX}/lib/openabe

cp -r deps/root/include/* ${PREFIX}/include/openabe
cp -r deps/root/lib/* ${PREFIX}/lib/openabe

cp cli/oabe_setup ${PREFIX}/bin
cp cli/oabe_keygen ${PREFIX}/bin
cp cli/oabe_enc ${PREFIX}/bin
cp cli/oabe_dec ${PREFIX}/bin
