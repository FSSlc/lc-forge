#!/bin/bash
set -ex

touch source.cc
libtool --tag=CXX --mode=compile $CXX -c -o source.lo -fsanitize=address source.cc
libtool --tag=CXX --mode=link $CXX -fsanitize=address -shared -o libsource.la source.lo
