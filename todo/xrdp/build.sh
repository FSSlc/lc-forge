#!/bin/bash
set -ex

# Create minimal crypt.h shim - libxcrypt provides libcrypt.so but not the header
cat > crypt.h << 'EOF'
#ifndef _CRYPT_H
#define _CRYPT_H
#ifdef __cplusplus
extern "C" {
#endif
char *crypt(const char *key, const char *salt);
#ifdef __cplusplus
}
#endif
#endif
EOF
export CFLAGS="${CFLAGS} -I$(pwd)"

autoreconf -vfi

./configure --prefix=$PREFIX \
            --sysconfdir=$PREFIX/etc \
            --localstatedir=$PREFIX/var \
            --disable-pam \
            --disable-pamuserpass \
            --enable-painter \
            --enable-rfxcodec \
            --enable-jpeg \
            --enable-pixman \
            --with-imlib2=yes \
            --with-freetype2=yes \
            --disable-fuse \
            --disable-fdkaac \
            --disable-opus \
            --disable-mp3lame \
            --disable-x264 \
            --disable-openh264 \
            --disable-smartcard \
            --disable-vsock \
            --disable-neutrinordp \
            --disable-ulalaca \
            --disable-xrdpvr \
            --disable-utmp \
            --enable-ipv6 \
            --disable-rdpsndaudin

find . -name Makefile -exec sed -i 's/-Werror//g' {} +

make -j${CPU_COUNT}
make install
