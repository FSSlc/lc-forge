#!/bin/bash

export CFLAGS="-I${PREFIX}/include"
#export LDFLAGS="-L${PREFIX}/lib"
export LDFLAGS="${LDFLAGS} -Wl,-rpath-link,${PREFIX}/lib"
./configure  --prefix=$PREFIX ##--disable-static
make
make install
