#!/usr/bin/env bash
# Build CRUISE — user-space POSIX-like file system in main memory.
#
# Reference: afepack recipe (same autotools pattern: autoreconf + configure + make).
set -Eeuo pipefail

# upstream prepare script: autoreconf -fvi
autoreconf -fvi

# CRUISE interposes the stdio symbols (cruise-stdio.c defines its own fprintf /
# vfprintf wrappers), which clashes with the fortified glibc helpers enabled by
# the toolchain's -D_FORTIFY_SOURCE=2: gcc reports
#   bits/stdio2.h:95:1: error: inlining failed in call to 'always_inline'
#   'fprintf.localalias': redefined extern inline functions are not considered
#   for inlining
# Turning fortification off for this package is the usual fix for libraries that
# wrap libc symbols. CPPFLAGS is baked into the generated Makefile by configure,
# so it has to be set here rather than passed to make.
export CPPFLAGS="${CPPFLAGS:-} -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"

# This is pre-GCC-10 code: src/cruise-internal.h declares shared state as
# tentative definitions (`int cruise_spilloverblock;`), which clash under the
# -fno-common default of modern gcc ("multiple definition of
# `cruise_spilloverblock'"). Build with the old -fcommon behaviour.
export CFLAGS="${CFLAGS:-} -fcommon"

# cruise.c calls numa_* unconditionally, and the LD_PRELOAD library itself uses
# dlsym, but the upstream rule that links libcruise.so passes -ldl *before* the
# objects and never adds the numa libraries. With conda's --as-needed those
# libraries are dropped, leaving libcruise.so with unresolved numa_* / dlsym
# symbols, so `LD_PRELOAD=libcruise.so <cmd>` dies with "symbol lookup error".
# LDFLAGS is expanded before the objects in that rule, hence --no-as-needed.
export LDFLAGS="${LDFLAGS:-} -Wl,--no-as-needed -lnuma -ldl -Wl,--as-needed"

./configure \
  --prefix="${PREFIX}" \
  --with-numa="${PREFIX}" \
  --enable-ld-preload

make -j"${CPU_COUNT}"
make install