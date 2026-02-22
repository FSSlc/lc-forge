#!/bin/bash

mkdir -p build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_JAVA_COMPILE_FLAGS=-Xlint:deprecation,unchecked,-serial,-cast,-unchecked,-rawtypes \
      -DTVNC_BUILDVIEWER=ON -DTVNC_INCLUDEJRE=OFF \
      -DTVNC_NVCONTROL=OFF -DTVNC_USEPAM=OFF \
      -DX11_ICE_LIB=$PREFIX/lib/libICE.so \
      -DX11_SM_LIB=$PREFIX/lib/libSM.so \
      -DX11_X11_LIB=$PREFIX/lib/libX11.so \
      -DX11_X11_xcb_LIB=$PREFIX/libX11-xcb.so \
      -DX11_Xau_LIB=$PREFIX/lib/libXau.so \
      -DX11_Xext_LIB=$PREFIX/lib/libXext.so \
      -DX11_Xfixes_LIB=$PREFIX/lib/libXfixes.so \
      -DX11_Xi_LIB=$PREFIX/lib/libXi.so \
      -DX11_Xt_LIB=$PREFIX/lib/libXt.so \
      -DX11_Xrender_LIB=$PREFIX/lib/libXrender.so \
      -DX11_xcb_LIB=$PREFIX/lib/libxcb.so \
      -DX11_xcb_randr_LIB=$PREFIX/lib/libxcb-randr.so \
      -DX11_xcb_xfixes_LIB=$PREFIX/lib/libxcb-xfixes.so \
      -DX11_xcb_xtest_LIB=$PREFIX/lib/libxcb-xtest.so \
      -DCMAKE_EXE_LINKER_FLAGS=-liconv \
      -DXKB_BASE_DIRECTORY=$PREFIX/share/X11/xkb \
      -DCMAKE_INSTALL_PREFIX=$PREFIX \
      -DCMAKE_INSTALL_SYSCONFDIR=$PREFIX/etc \
      -B build -S .

cmake --build build --target install -- -j${CPU_COUNT}

chmod 644 $PREFIX/etc/turbovncserver-security.conf
sed -i "1c #! $PREFIX/bin/python" $PREFIX/bin/webserver
cp $PREFIX/share/X11/xkb/rules/base $PREFIX/share/X11/xkb/rules/xorg
