#!/usr/bin/env bash
# Build CRUISE — user-space POSIX-like file system in main memory.
#
# Reference: afepack recipe (same autotools pattern: autoreconf + configure + make).
set -Eeuo pipefail

# upstream prepare script: autoreconf -fvi
autoreconf -fvi

./configure \
  --prefix="${PREFIX}" \
  --with-numa="${PREFIX}" \
  --enable-ld-preload

make -j"${CPU_COUNT}"
make install