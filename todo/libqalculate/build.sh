#!/usr/bin/env bash
# libqalculate ships a pre-generated configure script, so no autoreconf is needed.
set -Eeuo pipefail

# --enable-compiled-definitions bakes units.xml/functions.xml/etc. into the
# library instead of loading them from "$(datadir)/qalculate" at runtime. We
# need this because the autoconf datadir is embedded as an absolute path that
# rattler-build does not relocate: the shipped binary would otherwise look for
# share/qalculate/ under the CI runner's build prefix and print
# "Failed to load global definitions!".
./configure \
  --prefix="${PREFIX}" \
  --disable-static \
  --enable-shared \
  --with-readline \
  --enable-compiled-definitions

make -j"${CPU_COUNT}"

# `make check` drives the unittest runner, which walks tests/*.batch and feeds
# every expression to `qalc --test-file`.  The suite is offline and deterministic
# (fixed expected values, no relative dates) and is only runnable natively.
if [[ "${build_platform}" == "${target_platform}" ]]; then
  make check -j"${CPU_COUNT}"
fi

make install
