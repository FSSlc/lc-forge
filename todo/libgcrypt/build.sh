#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${target_platform}" == linux-* ]]; then
  export CFLAGS=${CFLAGS//-O2/}
  export CPPFLAGS=${CPPFLAGS//-O2/}
  export CXXFLAGS=${CXXFLAGS:-}
  export CXXFLAGS=${CXXFLAGS//-O2/}
elif [[ "${target_platform}" == osx-* ]]; then
  export ac_cv_sys_symbol_underscore=yes
fi

# The release tarball already ships a configure script, so skip autogen.sh.
./configure --prefix="${PREFIX}" --disable-static

make -j"${CPU_COUNT:-1}"
make install

# libtool archives are not used by conda packages
rm -f "${PREFIX}"/lib/*.la
