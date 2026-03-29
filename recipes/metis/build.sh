#!/bin/bash

make config prefix=$PREFIX

make -j $CPU_COUNT
make install
