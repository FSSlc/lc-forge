#!/bin/bash
set -ex

# Wi4MPI ships its generated sources inside the release tarball under
# build/src, and CMakeLists.txt only accepts that pre-generated tree when
# CMAKE_BINARY_DIR is exactly <source>/build (see the WI4MPI_GENERATOR=OFF
# branch). Configure there, after dropping the CMake state left by the release
# machine (CMake 3.20) -- the generated sources themselves are kept.
rm -rf "${SRC_DIR}/build/CMakeFiles" "${SRC_DIR}/build/src/CMakeFiles" \
       "${SRC_DIR}/build/src/Makefile" "${SRC_DIR}/build/src/cmake_install.cmake"

# CMAKE_POLICY_VERSION_MINIMUM: upstream still declares
# cmake_minimum_required(3.1), which CMake 4 refuses otherwise.
cmake -S "${SRC_DIR}" -B "${SRC_DIR}/build" \
      ${CMAKE_ARGS} \
      -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_BUILD_TYPE=Release

cmake --build "${SRC_DIR}/build" --parallel "${CPU_COUNT}"
cmake --install "${SRC_DIR}/build"
