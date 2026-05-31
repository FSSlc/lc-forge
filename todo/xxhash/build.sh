#!/bin/bash

set -euxo pipefail

export CFLAGS="${CFLAGS} -std=c99"

make CFLAGS="${CFLAGS}"
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" != "1" ]]; then
  make CFLAGS="${CFLAGS}" check test-xxhsum-c
fi
make CFLAGS="${CFLAGS}" install
