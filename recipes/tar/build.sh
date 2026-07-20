#!/bin/bash

set -euo pipefail

export FORCE_UNSAFE_CONFIGURE=1

mkdir -p $PREFIX/lib
cp $BUILD_PREFIX/share/gnuconfig/config.* build-aux/

if [[ "$target_platform" == osx-* ]]; then
  # This breaks the tests when the build is run as root (as on CI)
  export gl_cv_func_mknod_works=no
  export gl_cv_func_getcwd_abort_bug=no
fi

# iconv is detected during configure process but -liconv is missing
# from LDFLAGS as of gnu-tar 1.35. Remove once iconv linking works
# without this. See https://savannah.gnu.org/bugs/?64441.
# fix commit, http://git.savannah.gnu.org/cgit/tar.git/commit/?id=8632df39, remove in next release
if [[ "${target_platform}" == osx-* ]]; then
    export LDFLAGS="$LDFLAGS -lintl"
fi
export LDFLAGS="$LDFLAGS -liconv"
./configure --prefix=$PREFIX --with-libiconv-prefix=$PREFIX
make -j${CPU_COUNT}
make install

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" != "1" ]]; then
  # There are some known issues on older macOS releases
  if [[ "$target_platform" == "osx-64" ]]; then
    make installcheck "TESTSUITEFLAGS=-j${CPU_COUNT} 1-50 52-88 90-154 156-237" || (cat tests/testsuite.log; exit 1)
  else
    make installcheck || (cat tests/testsuite.log; exit 1)
  fi
fi
