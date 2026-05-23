#!/usr/bin/env bash

set -euxo pipefail

# This test fails on glibc <= 2.19, but it doesn't actually affect grep, so skip the test.
# https://lists.gnu.org/archive/html/bug-grep/2023-05/msg00015.html
echo "exit 77" > gnulib-tests/test-mbrlen5.sh

./configure                 \
    --prefix=${PREFIX}      \
    --build=${BUILD}        \
    --host=${HOST}          \
    --enable-threads=posix  \
    --enable-perl-regexp=yes

make -j${CPU_COUNT}

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" ]]; then
  # Don't run tests on emulated platforms, there expected paths don't match.
  make check
fi

make install
