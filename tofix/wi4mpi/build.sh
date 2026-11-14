#!/bin/bash
set -ex

# Wi4MPI ships its generated sources inside the release tarball under
# build/src, and CMakeLists.txt only accepts that pre-generated tree when
# CMAKE_BINARY_DIR is exactly <source>/build (see the WI4MPI_GENERATOR=OFF
# branch). Configure there, after dropping the CMake state left by the release
# machine (CMake 3.20) -- the generated sources themselves are kept.
rm -rf "${SRC_DIR}/build/CMakeFiles" "${SRC_DIR}/build/src/CMakeFiles" \
       "${SRC_DIR}/build/src/Makefile" "${SRC_DIR}/build/src/cmake_install.cmake"

# Wi4MPI installs a complete MPI implementation (bin/mpicc, bin/mpirun,
# include/mpi.h, lib/libmpi.so), so it goes under opt/ to coexist with a real
# MPI in the same prefix instead of fighting it over those paths.
#
# CMAKE_POLICY_VERSION_MINIMUM: upstream still declares
# cmake_minimum_required(3.1), which CMake 4 refuses otherwise.
cmake -S "${SRC_DIR}" -B "${SRC_DIR}/build" \
      ${CMAKE_ARGS} \
      -DCMAKE_INSTALL_PREFIX="${PREFIX}/opt/wi4mpi" \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_BUILD_TYPE=Release

cmake --build "${SRC_DIR}/build" --parallel "${CPU_COUNT}"
cmake --install "${SRC_DIR}/build"

# The wrapper compilers and the launcher read their settings from the
# environment, so export them on activation: everything wi4mpi looks up (its own
# tree, the compilers, the target MPI implementations) is resolved inside this
# conda prefix.
mkdir -p "${PREFIX}/etc/conda/activate.d" "${PREFIX}/etc/conda/deactivate.d"

cat > "${PREFIX}/etc/conda/activate.d/wi4mpi_activate.sh" <<'EOF'
export WI4MPI_ROOT="${CONDA_PREFIX}/opt/wi4mpi"
export PATH="${WI4MPI_ROOT}/bin:${PATH}"
# mpicc/mpicxx/mpifort take their compiler from these variables: use the
# toolchain of this prefix (its activation exports CC/CXX/FC) and fall back to
# the prefix's own gcc/g++/gfortran.
export WI4MPI_CC="${WI4MPI_CC:-${CC:-${CONDA_PREFIX}/bin/gcc}}"
export WI4MPI_CXX="${WI4MPI_CXX:-${CXX:-${CONDA_PREFIX}/bin/g++}}"
export WI4MPI_FC="${WI4MPI_FC:-${FC:-${CONDA_PREFIX}/bin/gfortran}}"
# Target MPI implementations are searched in <root>/lib and <root>/lib64.
export OPENMPI_ROOT="${OPENMPI_ROOT:-${CONDA_PREFIX}}"
export MPICH_ROOT="${MPICH_ROOT:-${CONDA_PREFIX}}"
EOF

cat > "${PREFIX}/etc/conda/deactivate.d/wi4mpi_deactivate.sh" <<'EOF'
if [ -n "${WI4MPI_ROOT:-}" ]; then
    _wi4mpi_path=""
    _wi4mpi_ifs="${IFS}"
    IFS=":"
    for _wi4mpi_entry in ${PATH}; do
        if [ "${_wi4mpi_entry}" != "${WI4MPI_ROOT}/bin" ]; then
            _wi4mpi_path="${_wi4mpi_path:+${_wi4mpi_path}:}${_wi4mpi_entry}"
        fi
    done
    IFS="${_wi4mpi_ifs}"
    export PATH="${_wi4mpi_path}"
    unset _wi4mpi_path _wi4mpi_ifs _wi4mpi_entry
fi
unset WI4MPI_ROOT WI4MPI_CC WI4MPI_CXX WI4MPI_FC OPENMPI_ROOT MPICH_ROOT
EOF
