#!/usr/bin/env bash
make prefix=$PREFIX CFLAGS="-I$PREFIX/include $CFLAGS" LDFLAGS="$LDFLAGS" CFLAGS_OS=-I$PREFIX/include status
make prefix=$PREFIX CFLAGS="-I$PREFIX/include $CFLAGS" LDFLAGS="$LDFLAGS" CFLAGS_OS=-I$PREFIX/include all
make prefix=$PREFIX CFLAGS="-I$PREFIX/include $CFLAGS" LDFLAGS="$LDFLAGS" CFLAGS_OS=-I$PREFIX/include install
