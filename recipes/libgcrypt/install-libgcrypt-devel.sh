#!/usr/bin/env bash

set -euo pipefail

make install
rm $PREFIX/bin/dumpsexp
rm $PREFIX/bin/hmac256
rm $PREFIX/bin/mpicalc
