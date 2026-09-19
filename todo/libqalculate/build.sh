#!/usr/bin/env bash
# libqalculate ships a pre-generated configure script, so no autoreconf is needed.
set -Eeuo pipefail

export PKG_CONFIG_PATH=${BUILD_PREFIX}/lib/pkgconfig

./configure \
  --prefix="${PREFIX}" \
  --disable-static \
  --enable-shared \
  --with-readline

make -j"${CPU_COUNT}"

# `make check` drives the unittest runner, which walks tests/*.batch and feeds
# every expression to `qalc --test-file`.  The suite is offline and deterministic
# (fixed expected values, no relative dates) and is only runnable natively.
if [[ "${build_platform}" == "${target_platform}" ]]; then
  make check -j"${CPU_COUNT}"
fi

make install
