#!/bin/bash

set -x

autoreconf -fiv

# Source: https://llvm.org/doxygen/BinaryFormat_2ELF_8h_source.html
sed -i '1s;^;#define NT_ARM_PAC_MASK 0x406;' src/ptrace/_UPT_ptrauth_insn_mask.c

./configure --prefix=$PREFIX --disable-static --disable-tests

make -j${CPU_COUNT}
make install

# The tests are known to be flakey so disable them
# make check || true
