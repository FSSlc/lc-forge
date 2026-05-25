#!/bin/env bash

FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=$PREFIX

make -j $CPU_COUNT
make install
make installcheck
