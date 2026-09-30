#!/bin/sh

set -euo pipefail

pushd libltdl
./configure --prefix=${PREFIX} --enable-ltdl-install --disable-static
make
make install
