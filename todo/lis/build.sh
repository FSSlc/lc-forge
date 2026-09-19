#!/bin/bash
set -ex

# LIS ships pre-generated autotools files; use the current config.guess /
# config.sub for the target platform.
cp -f ${BUILD_PREFIX}/share/gnuconfig/config.* config/

# LIS links its shared library without the Fortran/MPI runtime libraries, so
# liblis.so would keep _gfortran_* / mpi_*_ undefined and a C consumer of lis.h
# would die at run time with "symbol lookup error". LIBS is appended to the
# library link line, so add them explicitly.
export LIBS="-lmpifort -lgfortran"

# --enable-omp    OpenMP parallelization
# --enable-mpi    MPI (mpicc/mpif90 found on PATH from mpich)
# --enable-fortran  Fortran 77 compatible interface (lisf.h)
# --enable-f90      Fortran 90 interface
# --enable-saamg    SA-AMG preconditioner, implemented in Fortran 90
# Upstream's configure defaults to AC_DISABLE_SHARED; build a shared library.
./configure --prefix=${PREFIX} \
  --enable-shared \
  --disable-static \
  --enable-omp \
  --enable-mpi \
  --enable-fortran \
  --enable-f90 \
  --enable-saamg

make -j${CPU_COUNT}

# Upstream test suite: linear solvers, eigensolvers, the Fortran interface and
# SA-AMG, each run on 2 MPI ranks with OMP_NUM_THREADS=2.
make check

make install
