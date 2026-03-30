#!/bin/bash

make config shared=1 prefix=$PREFIX

make -j $CPU_COUNT
make install
