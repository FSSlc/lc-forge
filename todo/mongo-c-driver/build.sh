#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p build
cd build

# mongo-c-driver 2.x CMake options (see upstream CMakeLists / Fedora packaging).
# - Builds bundled libbson together with libmongoc (USE_SYSTEM_LIBBSON=OFF).
# - Shared only; no static archives.
# - OpenSSL for TLS; system zlib + zstd for compression.
# - SASL and libmongocrypt left off to keep the dependency set small/portable.
cmake "${CMAKE_ARGS}" .. \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DENABLE_MONGOC=ON \
  -DENABLE_SHARED=ON \
  -DENABLE_STATIC=OFF \
  -DENABLE_TESTS=OFF \
  -DENABLE_EXAMPLES=OFF \
  -DENABLE_MAN_PAGES=OFF \
  -DENABLE_HTML_DOCS=OFF \
  -DENABLE_UNINSTALL=OFF \
  -DENABLE_SSL=OPENSSL \
  -DENABLE_SASL=OFF \
  -DENABLE_SNAPPY=AUTO \
  -DENABLE_ZLIB=SYSTEM \
  -DENABLE_ZSTD=ON \
  -DENABLE_CLIENT_SIDE_ENCRYPTION=OFF \
  -DUSE_BUNDLED_UTF8PROC=ON \
  -DUSE_SYSTEM_LIBBSON=OFF

cmake --build . --config Release --parallel "${CPU_COUNT}"
cmake --install . --config Release

# Drop any leftover static CMake package dirs if present.
rm -rf \
  "${PREFIX}/lib/cmake/bson-static-"* \
  "${PREFIX}/lib/cmake/mongoc-static-"* \
  "${PREFIX}/lib/pkgconfig/bson"*-static.pc \
  "${PREFIX}/lib/pkgconfig/mongoc"*-static.pc
