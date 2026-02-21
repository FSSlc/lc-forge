#!/usr/bin/env bash

# py3.patch modifies configure.ac
autoreconf -ifv

PKG_CONFIG_PATH=$BUILD_PREFIX/lib/pkgconfig:$BUILD_PREFIX/$HOST/sysroot/usr/lib64/pkgconfig \
./configure --prefix=$PREFIX \
    --with-x \
    --enable-startup-notification \
    --sysconfdir=$PREFIX/etc \
    --libexecdir=$PREFIX/libexec/

make -j${CPU_COUNT} install

$CC -o setlayout ./setlayout.c -lX11 -I$PREFIX/include
install -m644 -p setlayout $PREFIX/bin/setlayout
install -p xdg-menu $PREFIX/libexec/openbox-xdg-menu
sed 's|_LIBEXECDIR_|"$PREFIX/libexec"/|g' < menu.xml \
        > $PREFIX/etc/xdg/openbox/menu.xml
install -m644 -p terminals.menu $PREFIX/etc/xdg/openbox/terminals.menu
