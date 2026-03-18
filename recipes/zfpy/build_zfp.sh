#!/usr/bin/env bash
set -e

mkdir build
cd build
cmake ${CMAKE_ARGS}                \
  -DBUILD_CFP=ON                   \
  -DBUILD_UTILITIES=ON             \
  -DZFP_WITH_OPENMP=ON             \
  -DCMAKE_INSTALL_PREFIX=${PREFIX} \
  -DCMAKE_PREFIX_PATH=${PREFIX}    \
  -DCMAKE_INSTALL_LIBDIR=lib       \
  ..

make -j${CPU_COUNT}
if [[ "$CONDA_BUILD_CROSS_COMPILATION" != "1" ]]; then
  make test
fi
make install

mkdir -p ${PREFIX}/bin
# Binary not install correctly by cmake
install bin/zfp ${PREFIX}/bin/.

if [[ "$CONDA_BUILD_CROSS_COMPILATION" != "1" ]]; then
  ./bin/testzfp
fi
