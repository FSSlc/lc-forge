#! /usr/bin/env bash

# Workaround for leftover build directory paths in HDF5 installation
# https://github.com/HDFGroup/hdf5/issues/2422
sed -i.tmp 's/-I.*H5FDsubfiling//' \
    "$(which h5cc)" \
    "$(which h5c++)"

mkdir _build && cd _build
cmake ${CMAKE_ARGS} \
    -DCMAKE_PREFIX_PATH=${PREFIX} \
    -DCMAKE_INSTALL_PREFIX=${PREFIX} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCGNS_BUILD_SHARED=ON \
    -DCGNS_USE_SHARED=ON \
    -DCGNS_ENABLE_FORTRAN=ON \
    -DFORTRAN_NAMING="LOWERCASE_" \
    -DCGNS_ENABLE_TESTS=ON \
    -DCGNS_ENABLE_LFS=ON \
    -DZZZCMAKE_C_FLAGS:STRING=-D_LARGEFILE64_SOURCE \
    -DCGNS_ENABLE_HDF5=ON \
    -DHDF5_NEED_SZIP=OFF \
    -DHDF5_NEED_ZLIB=ON \
    -DCGNS_BUILD_CGNSTOOLS=ON \
    ..

make install -j$CPU_COUNT
if [[ `uname -s` == 'Linux' ]]; then
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR}" != "" ]]; then
    ctest
fi
fi

# the build process installs some cgnstools binaries into ${CMAKE_INSTALL_PREFIX}/bin/cgnstools
# just move those into ${CMAKE_INSTALL_PREFIX}/bin
mv ${PREFIX}/bin/cgnstools/* ${PREFIX}/bin/
