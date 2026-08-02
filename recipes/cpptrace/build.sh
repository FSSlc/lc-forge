#!/bin/bash

echo "#########################################################################"
echo "Building ${PKG_NAME} using unwind back-end $unwind_backend"
echo "#########################################################################"

export CPPTRACE_UNWIND_WITH_LIBUNWIND=OFF
if [ "$unwind_backend" == "libunwind" ]; then
    export CPPTRACE_UNWIND_WITH_LIBUNWIND=ON
fi

cmake ${CMAKE_ARGS} -S . -B build -G "Ninja" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=On -DCPPTRACE_GET_SYMBOLS_WITH_LIBDWARF=On -DCPPTRACE_USE_EXTERNAL_LIBDWARF=On -DCPPTRACE_FIND_LIBDWARF_WITH_PKGCONFIG=On -DCPPTRACE_UNWIND_WITH_LIBUNWIND=$CPPTRACE_UNWIND_WITH_LIBUNWIND -DCMAKE_PREFIX_PATH=$PREFIX
cmake --build build --config Release --target install
