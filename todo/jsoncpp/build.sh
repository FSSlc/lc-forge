#!/bin/bash

set -x

cmake -LAH ${CMAKE_ARGS} -G Ninja \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_STATIC_LIBS=OFF \
  -DPYTHON_EXECUTABLE="${BUILD_PREFIX}/bin/python" \
  -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF \
  -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_CXX_STANDARD_REQUIRED=ON \
  -B build .
cmake --build build --target install -j${CPU_COUNT}

if [[ "$CONDA_BUILD_CROSS_COMPILATION" != "1" ]]; then
  ctest --test-dir build --output-on-failure
fi
