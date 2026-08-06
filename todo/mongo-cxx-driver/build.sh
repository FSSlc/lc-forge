#!/usr/bin/env bash
set -Eeuo pipefail

# The upstream 4.4.1 release tarball is created on macOS and contains
# AppleDouble "._*" files. CMake's file(GLOB_RECURSE ... "*.cpp") matches
# them and get_filename_component(NAME_WE) returns empty for them, producing
# broken example targets ("bsoncxx-", "mongocxx-mongodb.com-"). Strip them.
find mongo-cxx-driver-r* -type f -name '._*' -delete

# The mongo-c-driver package bakes its own build-env sysroot paths into the
# installed pkg-config and CMake configs (e.g. bson2.pc Libs:
# "-L<old-build-env>/x86_64-scns-linux-gnu/sysroot/usr/lib -lrt", and the
# mongo::detail::c_platform INTERFACE_LINK_LIBRARIES lists absolute
# librt.so/libm.so paths). Those paths never exist in a fresh build env, so
# rewrite them to plain -lrt / rt / m.
find "${PREFIX}" -type f \( -name "*.pc" -o -name "*.cmake" \) -print0 \
  | xargs -0 -r sed -i \
      -e 's|-L[^ ]*x86_64-[^/]*linux-gnu/sysroot/usr/lib||g' \
      -e 's|[^ ";]*x86_64-[^/]*linux-gnu/sysroot/usr/lib/librt\.so|rt|g' \
      -e 's|[^ ";]*x86_64-[^/]*linux-gnu/sysroot/usr/lib/libm\.so|m|g'

mkdir -p build
cd build

# mongo-cxx-driver 4.4.1 CMake flags
# - Uses bsoncxx + mongocxx targets from our mongo-c-driver recipe
# - Polyfill uses C++17 std library (no boost dep)
# - Shared only
# - DISABLED: static libs, shared with static mongoc, client-side encryption

cmake "${CMAKE_ARGS}" ../mongo-cxx-driver-r* \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_SHARED_AND_STATIC_LIBS=OFF \
  -DBUILD_SHARED_LIBS_WITH_STATIC_MONGOC=OFF \
  -DENABLE_TESTS=OFF \
  -DENABLE_UNINSTALL=OFF \
  -DENABLE_CODE_COVERAGE=OFF \
  -DCMAKE_CXX_STANDARD=17 \
  -DBSONCXX_POLY_USE_STD=ON \
  -DBUILD_VERSION="${PKG_VERSION}"

cmake --build . --config Release --parallel "${CPU_COUNT}"
cmake --install . --config Release

# Drop any leftover static CMake package dirs if present.
rm -rf \
  "${PREFIX}/lib/cmake/bsoncxx-static"* \
  "${PREFIX}/lib/cmake/mongocxx-static"* \
  "${PREFIX}/lib/pkgconfig/bsoncxx-static.pc" \
  "${PREFIX}/lib/pkgconfig/mongocxx-static.pc"
