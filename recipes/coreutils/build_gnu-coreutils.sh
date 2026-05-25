#!/bin/env bash

FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=$PREFIX --program-prefix=g

make -j $CPU_COUNT
make install
make installcheck
