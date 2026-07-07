#!/bin/bash

set -ex

constructor .

rm -rf /tmp/mesa
export tmp_prefix=/tmp/mesa/_h_env_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehol
bash mesa-24.2.8-*.sh -b -p $tmp_prefix

mkdir -p mesa/include
cp -rf $tmp_prefix/include/EGL mesa/include
cp -rf $tmp_prefix/include/GL mesa/include
cp -rf $tmp_prefix/include/GLES mesa/include
cp -rf $tmp_prefix/include/GLES2 mesa/include
cp -rf $tmp_prefix/include/GLES3 mesa/include
cp -rf $tmp_prefix/include/KHR mesa/include
cp -rf $tmp_prefix/include/directx mesa/include
cp -rf $tmp_prefix/include/dxguids mesa/include
cp -rf $tmp_prefix/include/wsl mesa/include
cp -rf $tmp_prefix/include/gbm.h mesa/include
# cp -rf $tmp_prefix/include/xa_*.h mesa/include

mkdir -p mesa/lib
cp -Prf $tmp_prefix/opt/mesa/lib/dri mesa/lib

cp -Prf $tmp_prefix/lib/libDirectX-Guids.a mesa/lib
cp -Prf $tmp_prefix/lib/libEGL.so* mesa/lib
cp -Prf $tmp_prefix/lib/libGL.so* mesa/lib
cp -Prf $tmp_prefix/lib/libGLESv1_CM.so* mesa/lib
cp -Prf $tmp_prefix/lib/libGLESv2.so* mesa/lib
cp -Prf $tmp_prefix/lib/libOSMesa.so* mesa/lib
cp -Prf $tmp_prefix/lib/libd3dx12-format-properties.a mesa/lib
cp -Prf $tmp_prefix/lib/libgallium-24.2.8.so mesa/lib
cp -Prf $tmp_prefix/lib/libgbm.so* mesa/lib
cp -Prf $tmp_prefix/lib/libglapi.so* mesa/lib
# cp -Prf $tmp_prefix/lib/libswrAVX2.so* mesa/lib
# cp -Prf $tmp_prefix/lib/libswrAVX.so* mesa/lib
# cp -Prf $tmp_prefix/lib/libxatracker.so* mesa/lib

cp -Prf $tmp_prefix/lib/libstdc++.so* mesa/lib
cp -Prf $tmp_prefix/lib/libgcc_s.so* mesa/lib
cp -Prf $tmp_prefix/lib/libLLVM*.so* mesa/lib
cp -Prf $tmp_prefix/lib/libzstd.so* mesa/lib
cp -Prf $tmp_prefix/lib/libz.so* mesa/lib
cp -Prf $tmp_prefix/lib/libdrm*.so* mesa/lib
cp -Prf $tmp_prefix/lib/libX11*.so* mesa/lib
cp -Prf $tmp_prefix/lib/libxcb*.so* mesa/lib
cp -Prf $tmp_prefix/lib/libXext*.so* mesa/lib
cp -Prf $tmp_prefix/lib/libxshmfence*.so* mesa/lib
cp -Prf $tmp_prefix/lib/libXxf86vm*.so* mesa/lib
cp -Prf $tmp_prefix/lib/libXfixes*.so* mesa/lib
cp -Prf $tmp_prefix/lib/libXdmcp*.so* mesa/lib

rm -rf $PREFIX/opt
mkdir -p $PREFIX/opt/
mv mesa $PREFIX/opt/

find $PREFIX/opt -type f | xargs  sed -i "s#$tmp_prefix#$PREFIX#g"
rm -rf /tmp/mesa

