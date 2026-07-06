#!/bin/bash

if [[ $target_platform =~ linux.* ]]; then
    USE_ICONV=--without-iconv
else
    USE_ICONV=--with-iconv
fi

autoreconf -vfi
mkdir -p build-minimal-${HOST} && cd build-minimal-${HOST}

${SRC_DIR}/configure --prefix=${PREFIX}  \
                     --with-zlib         \
                     --with-bz2lib       \
                     --with-zstd         \
                     --enable-static     \
                     --disable-shared    \
                     ${USE_ICONV}        \
                     --without-lzma      \
                     --without-lzo2      \
                     --without-cng       \
                     --without-openssl   \
                     --without-nettle    \
                     --without-xml2      \
                     --without-expat     \

make -j${CPU_COUNT} ${VERBOSE_AT}
make install
