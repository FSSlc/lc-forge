#!/bin/bash
set -ex

if [[ "$CONDA_BUILD_CROSS_COMPILATION" == 1 ]]; then
  (
    export CC=$CC_FOR_BUILD
    export CXX=$CXX_FOR_BUILD
    export AR=($CC_FOR_BUILD -print-prog-name=ar)
    export NM=($CC_FOR_BUILD -print-prog-name=nm)
    export LDFLAGS=${LDFLAGS//$PREFIX/$BUILD_PREFIX}
    export PKG_CONFIG_PATH=${BUILD_PREFIX}/lib/pkgconfig

    # Unset them as we're ok with builds that are either slow or non-portable
    unset CFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    # The cross-compile CMAKE_PREFIX_PATH points at the target (e.g. aarch64)
    # sysroot.  Leaving it set makes the bundled libarchive's find_path() resolve
    # target headers (e.g. iconv.h) into the native (build-arch) compile, leaking
    # the target sysroot include path onto every cmlibarchive target.  That causes
    # a header/libc mismatch: CHECK_FUNCTION_EXISTS_GLIBC finds newer glibc
    # symbols (arc4random_buf, closefrom, close_range, ...) in the build-arch libc
    # but the target stdlib.h/unistd.h don't declare them yet, so the compile fails
    # with an implicit-declaration error.  The cache -DCMAKE_PREFIX_PATH below is
    # already restricted to ${BUILD_PREFIX}, so dropping the env var makes the
    # native build use build-arch headers consistently.
    unset CMAKE_PREFIX_PATH

    mkdir -p build-native
    pushd build-native
    ../bootstrap \
             --verbose \
             --prefix="${BUILD_PREFIX}" \
             --no-system-libs \
             --no-qt-gui \
             --parallel=${CPU_COUNT} \
             -- \
             -DCMAKE_BUILD_TYPE:STRING=Release \
             -DCMAKE_FIND_ROOT_PATH="${BUILD_PREFIX}" \
             -DCMAKE_INSTALL_RPATH="${BUILD_PREFIX}/lib" \
             -DCURSES_INCLUDE_PATH="${BUILD_PREFIX}/include" \
             -DBUILD_CursesDialog=OFF \
             -DCMAKE_USE_OPENSSL=OFF \
             -DCMake_HAVE_CXX_MAKE_UNIQUE:INTERNAL=FALSE \
             -DCMAKE_PREFIX_PATH="${BUILD_PREFIX}" || (cat Bootstrap.cmk/cmake_bootstrap.log; exit 1)

    make install -j${CPU_COUNT}
    popd
  )

  # Keep the target sysroot in CMAKE_FIND_ROOT_PATH (do NOT collapse it to just
  # ${PREFIX}).  The build-cross phase compiles FOR the target arch, so the
  # target sysroot headers are the correct ones to find here (unlike the
  # build-native phase above, which must use build-arch headers).  CMake 4.4's
  # bundled libarchive made iconv mandatory: its find_path(ICONV_INCLUDE_DIR
  # iconv.h) only resolves iconv.h out of CMAKE_FIND_ROOT_PATH (MODE_INCLUDE=ONLY),
  # so dropping the sysroot leaves ICONV_INCLUDE_DIR empty -> HAVE_ICONV stays
  # false -> "iconv is required, but was not found."  With the sysroot present
  # find_path finds <sysroot>/usr/include/iconv.h and iconv() in libc, matching
  # the main cmake feedstock's (working) cross build.
  CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_FIND_ROOT_PATH=${PREFIX};${CONDA_BUILD_SYSROOT} -DCMAKE_INSTALL_RPATH=${PREFIX}/lib"
  CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_PREFIX_PATH=${PREFIX}"
  mkdir build-cross
  pushd build-cross
  cmake ${CMAKE_ARGS} \
     -DCMAKE_VERBOSE_MAKEFILE=1 \
     -DCMAKE_INSTALL_PREFIX=$PREFIX \
     -DBUILD_QtDialog=OFF \
     -DCMAKE_USE_OPENSSL=OFF \
     -DBUILD_CursesDialog=OFF \
     -DCMake_HAVE_CXX_MAKE_UNIQUE:INTERNAL=FALSE \
     -DCMake_HAVE_CXX_FILESYSTEM=1 \
     -DHAVE_POLL_FINE_EXITCODE=0 -DHAVE_POLL_FINE_EXITCODE__TRYRUN_OUTPUT="" \
     -DCMAKE_USE_SYSTEM_LIBRARY_LIBARCHIVE=OFF \
     -DCMAKE_USE_SYSTEM_LIBRARY_JSONCPP=OFF \
     .. || (cat TryRunResults.cmake; false)

  make install -j${CPU_COUNT}
else

  if [[ "${target_platform}" == osx-* ]]; then
    CFLAGS="${CFLAGS} -DTARGET_OS_IPHONE=0 -DTARGET_OS_WATCH=0 -DTARGET_OS_TV=0"
  fi

  ./bootstrap \
               --verbose \
               --prefix="${PREFIX}" \
               --no-system-libs \
               --no-qt-gui \
               --parallel=${CPU_COUNT} \
               -- \
               -DCMAKE_BUILD_TYPE:STRING=Release \
               -DCMAKE_FIND_ROOT_PATH="${PREFIX}" \
               -DCMAKE_INSTALL_RPATH="${PREFIX}/lib" \
               -DCURSES_INCLUDE_PATH="${PREFIX}/include" \
               -DBUILD_CursesDialog=OFF \
               -DCMAKE_USE_OPENSSL=OFF \
               -DCMake_HAVE_CXX_MAKE_UNIQUE:INTERNAL=FALSE \
               -DCMAKE_PREFIX_PATH="${PREFIX}"

  # CMake automatically selects the highest C++ standard available
  make install -j${CPU_COUNT}
fi
