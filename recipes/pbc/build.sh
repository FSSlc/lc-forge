#!/bin/bash

./configure --prefix=$PREFIX
CPATH=$BUILD_PREFIX/include make install -j
