#!/bin/env bash

./configure --prefix=$PREFIX --program-prefix=g

make -j $CPU_COUNT
make install
make installcheck
