#!/bin/bash

mkdir -p build
cd build

export LD_LIBRARY_PATH=${BUILD_PREFIX}/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=${SRC_DIR}/build/lib:$LD_LIBRARY_PATH

cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
      -DBUILD_SHARED_LIBS=ON \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DADIOS2_BUILD_EXAMPLES=OFF \
      -DBUILD_TESTING=OFF \
      -DADIOS2_USE_MPI=ON \
      -DADIOS2_USE_Campaign=OFF \
      -DADIOS2_USE_Fortran=ON \
      ${SRC_DIR}

make -j $CPU_COUNT install
