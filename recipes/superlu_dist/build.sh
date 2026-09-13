#!/usr/bin/env bash

set -ex
export CFLAGS="$CFLAGS -std=c99 -fPIC"

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" ]]; then
    WITH_TESTS=ON
else
    WITH_TESTS=OFF
fi

# workaround until https://github.com/conda-forge/clang-compiler-activation-feedstock/pull/70 is merged
CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_PROGRAM_PATH=${BUILD_PREFIX}/bin;$PREFIX/bin"

WORK=$PWD

mkdir build
cd build

cmake .. \
    ${CMAKE_ARGS} \
    -DCMAKE_C_FLAGS="${CFLAGS}" \
    -DCMAKE_C_COMPILER="${CC}" \
    -DCMAKE_CXX_COMPILER="${CXX}" \
    -DCMAKE_Fortran_COMPILER="${FC}" \
    -DCMAKE_Fortran_FLAGS="${FFLAGS}" \
    -DCMAKE_INSTALL_INCLUDEDIR=include/superlu-dist \
    -DCMAKE_BUILD_TYPE=RELEASE \
    -DTPL_ENABLE_PARMETISLIB=ON \
    -DTPL_PARMETIS_INCLUDE_DIRS="${PREFIX}/include" \
    -DTPL_PARMETIS_LIBRARIES="${PREFIX}/lib/libparmetis${SHLIB_EXT};${PREFIX}/lib/libmetis${SHLIB_EXT}" \
    -DTPL_BLAS_LIBRARIES="${PREFIX}/lib/libblas${SHLIB_EXT}" \
    -DTPL_ENABLE_LAPACKLIB=ON \
    -DTPL_LAPACK_LIBRARIES="${PREFIX}/lib/liblapack${SHLIB_EXT};${PREFIX}/lib/libblas${SHLIB_EXT}" \
    -DTPL_ENABLE_INTERNAL_BLASLIB=OFF \
    -DXSDK_ENABLE_Fortran=ON \
    -Denable_tests=${WITH_TESTS} \
    -Denable_examples=OFF \
    -Denable_python=OFF \
    -Denable_doc=OFF \
    -DBUILD_STATIC_LIBS=OFF \
    -DBUILD_SHARED_LIBS=ON

cmake --build . --parallel ${CPU_COUNT:-1}

# ctest seems to have weird PATH assumptions
export PATH=$PWD/EXAMPLE:$PWD/TEST:$PATH

# debug mpich
export MPIR_CVAR_DEBUG_SUMMARY=1 
export FI_PROVIDER=tcp

# avoid heavy oversubscription of resources: already 1-2 MPI ranks (processes)
export OMP_NUM_THREADS=1
export KMP_NUM_THREADS=${OMP_NUM_THREADS}
export MKL_NUM_THREADS=${OMP_NUM_THREADS}
export CTEST_REGEX="-R (pdtest_1x1|pdtest_1x2|pdtest_2x1|pddrive)"
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR}" != "" ]]; then
    ctest --output-on-failure ${CTEST_REGEX}
fi

cmake --install .
