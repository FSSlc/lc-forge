#!/bin/bash
set -Eeuo pipefail

# Upstream git tags ship the autotools inputs (configure.ac, Makefile.am, m4/)
# but no generated `configure`; bootstrap before configuring.  `autoreconf -i`
# honours AC_CONFIG_MACRO_DIR(m4) / AC_CONFIG_AUX_DIR(build-aux) and installs
# the missing auxiliary files.
autoreconf -vif

# PLE probes MPI through the compiler wrapper (see PLE_AC_TEST_MPI in
# m4/ple_mpi.m4): with CC=mpicc the link test succeeds, the coupling sources
# are compiled, and libtool links libple.so against libmpi.
export CC=mpicc

./configure --prefix="${PREFIX}"

make -j"${CPU_COUNT}"
make install