
#!/usr/bin/env bash

mkdir build
cd build

# Check which output we're building
if [[ $PKG_NAME == "libmsgpack-c-static" ]]; then
    export MSGPACK_BUILD_SHARED_LIBS=OFF
else
    export MSGPACK_BUILD_SHARED_LIBS=ON
fi

cmake ${CMAKE_ARGS} \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DBUILD_SHARED_LIBS=${MSGPACK_BUILD_SHARED_LIBS} \
    ..

ninja install
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR}" != "" ]]; then
ctest
fi
