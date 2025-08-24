#!/usr/bin/env bash

sed  -i 's/^CC = gcc/CC ?= gcc\nCC = \$(GCC)/' Makefile  
make all
make PREFIX=$PREFIX install
