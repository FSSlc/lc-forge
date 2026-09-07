#!/bin/bash
# Structural CI tests for opencode-desktop. These run headless in the build
# container (no X server, no GTK), so they only verify packaging invariants.
set -Eeuo pipefail

app="$PREFIX/opencode-desktop"

echo "== opencode-desktop package test =="

test -x "$PREFIX/bin/opencode-desktop"
echo "launcher present: OK"

bash -n "$PREFIX/bin/opencode-desktop"
echo "launcher syntax: OK"

test -x "$app/ai.opencode.desktop"
echo "main binary: OK"

interp="$(patchelf --print-interpreter "$app/ai.opencode.desktop")"
echo "interpreter: $interp"
case "$interp" in
  "$PREFIX/opencode-desktop/sysroot/lib64/"*) ;;
  *)
    echo "unexpected interpreter: $interp" >&2
    exit 1
    ;;
esac

test -x "$interp"
echo "bundled loader: OK"

test -f "$app/sysroot/lib64/libc.so.6"
echo "bundled glibc: OK"

# Regression guard: rattler-build's binary relocation must never touch the
# bundled sysroot. If patchelf ever rewrites the loader (e.g. injecting an
# RPATH) it corrupts glibc and the app dies inside _dl_start with SIGSEGV.
loader="$(ls "$app/sysroot/lib64"/ld-linux-* 2>/dev/null | head -1)"
if readelf -d "$loader" 2>/dev/null | grep -qiE 'runpath|rpath'; then
  echo "bundled loader has RPATH/RUNPATH (corrupted by binary relocation): $loader" >&2
  exit 1
fi
echo "bundled loader pristine: OK"

grep -q '/sysroot/lib64' "$PREFIX/bin/opencode-desktop"
echo "launcher env: OK"

echo "== all checks passed =="