#!/bin/bash
set -Eeuo pipefail

# The third-party libraries are fetched into $SRC_DIR/extlib by rattler-build;
# land them inside the source tree where load_extlib.py expects (../extlib
# relative to starter/ and engine/).  With extlib/EXTLIB_VERSION.json in place
# the loader matches the requested version and never downloads.
rm -rf "${SRC_DIR}/openradioss/extlib"
mv "${SRC_DIR}/extlib" "${SRC_DIR}/openradioss/extlib"

# The first source entry (OpenRadioss tarball) is placed into openradioss/
# but rattler-build does not extract it when target_directory is set.
# We extract it manually and strip the leading directory that GitHub archives
# always include (OpenRadioss-latest-20260728/).
cd "${SRC_DIR}/openradioss"
# Extract the GitHub archive tarball (filename varies).
for f in *.tar.gz; do
  if [ -f "$f" ]; then
    tar xzf "$f" --strip-components=1
    rm -f "$f"
  fi
done
cd "${SRC_DIR}/openradioss"

case "${target_platform}" in
  linux-64)
    or_arch=linux64_gf
    extlib_arch=linux64
    ;;
  linux-aarch64)
    or_arch=linuxa64_gf
    extlib_arch=linuxa64
    ;;
  *)
    echo "unsupported target_platform: ${target_platform}" >&2
    exit 1
    ;;
esac

# GitHub archives do not preserve the executable bit.
chmod +x starter/build_script.sh engine/build_script.sh

# Patch: move my_real typedef outside PYTHON_DISABLED guard.
# The upstream CMake compiler config always compiles cpp_python_funct.cpp with
# -DPYTHON_DISABLED, which skips the typedef but keeps the stub functions that
# use it.  We add the typedef before the guard and delete the guarded copy.
PYTHON_FUNCT="${SRC_DIR}/openradioss/common_source/modules/cpp_python_funct.cpp"
python3 -c "
lines = open('${PYTHON_FUNCT}').readlines()
# Find insertion point (after #include <limits>)
for i, l in enumerate(lines):
    if l.strip() == '#include <limits>':
        insert_at = i + 1
        break
# Insert my_real typedef
typedef = [
    '#ifdef MYREAL8\n',
    '// double precision define my_real as double\n',
    'typedef double my_real;\n',
    '#else\n',
    'typedef float my_real;\n',
    '#endif\n',
]
lines[insert_at:insert_at] = typedef
# Remove the guarded copy inside PYTHON_DISABLED guard
for i, l in enumerate(lines):
    if l.strip() == '#ifdef MYREAL8' and i > insert_at:
        del lines[i:i+6]
        break
open('${PYTHON_FUNCT}', 'w').writelines(lines)
"

# Also add missing stub functions that python_mod.F90 and engine Python coupling
# code expect even when PYTHON_DISABLED is defined (upstream oversight).
# These need to be added before the closing '}' of the extern C block.
sed -i '/^    void cpp_python_load_environment() {}/a\
    void cpp_python_update_active_node(int numnod, int name_len, char *name, double *values) {}\
    void cpp_python_update_active_node_ids(int *user_ids, int *cond_type) {}\
    void cpp_python_add_ints_to_dict(char *dict_name, int *values, int num_vals) {}\
    void cpp_python_add_doubles_to_dict(char *dict_name, double *values, int num_vals) {}\
    void cpp_python_update_reals(char *basename, int *uid, double *reals, int num_reals) {}\
    void cpp_python_create_context(char *name) {}\
    void cpp_python_sync() {}' "${PYTHON_FUNCT}"

# The upstream CMake build adds -Werror for Fortran (via CMake_Compilers/*.txt),
# but GCC 11 warns about potential uninitialized variables in third-party code.
for cfg in starter/CMake_Compilers/cmake_linux64_gf.txt \
           starter/CMake_Compilers/cmake_linuxa64_gf.txt \
           engine/CMake_Compilers/cmake_linux64_gf.txt \
           engine/CMake_Compilers/cmake_linuxa64_gf.txt; do
  if [ -f "$cfg" ]; then
    sed -i 's/-Werror=maybe-uninitialized/-Wno-error=maybe-uninitialized/g' "$cfg"
  fi
done

# libuuid is a conda dependency but the upstream CMake flags drop the
# toolchain LDFLAGS, so $PREFIX/lib is not searched during linking.
# Help the linker find libuuid.so.1 via LIBRARY_PATH.
export LIBRARY_PATH="${LIBRARY_PATH:-}:${PREFIX}/lib"

# Patch the upstream CMake config to find OpenMPI in the conda build prefix
# (where the openmpi build dependency lives) instead of hardcoded /opt/openmpi/.
MPI_PREFIX="${BUILD_PREFIX}"
for cfg in engine/CMake_Compilers/cmake_linux64_gf.txt \
           engine/CMake_Compilers/cmake_linuxa64_gf.txt; do
  [ -f "$cfg" ] || continue
  sed -i "s|/opt/openmpi/|${MPI_PREFIX}/|g" "$cfg"
done

# The engine build_script.sh uses `which gfortran` to find compilers, but the
# conda toolchain names them x86_64-scns-linux-gnu-gfortran etc.  Create
# symlinks so the upstream detection works.
: "${CC:=}" "${CXX:=}" "${FC:=}"  # ensure vars are bound for set -u
for compiler_var in "$CC" "$CXX" "$FC"; do
  [ -z "$compiler_var" ] && continue
  command -v "$compiler_var" >/dev/null 2>&1 || continue
  full_path="$(command -v "$compiler_var")"
  case "$full_path" in
    *-gfortran) simple=gfortran ;;
    *-g++|*-c++)  simple=g++ ;;
    *-gcc|*-cc) simple=gcc ;;
    *) continue ;;  # skip unknown patterns
  esac
  target_dir="${CONDA_BUILD_SYSROOT:+${BUILD_PREFIX}/bin}"
  target_dir="${target_dir:-${BUILD_PREFIX}/bin}"
  mkdir -p "$target_dir"
  [ -e "$target_dir/$simple" ] || ln -sf "$full_path" "$target_dir/$simple"
done
# Ensure BUILD_PREFIX/bin is first in PATH so these shims take precedence.
export PATH="${BUILD_PREFIX}/bin:${PATH}"

# The engine build_script.sh uses `which` which is not available in the conda
# build environment.  Provide a simple which(1) replacement via a shell function
# exported into the build subshells.
which() { command -v "$@"; }
export -f which

# Starter and Engine, SMP gfortran build (-release), without Python linking.
(
  cd starter
  ./build_script.sh -arch="${or_arch}" -release -mpi=ompi -no-python -nt="${CPU_COUNT}"
)
(
  cd engine
  # Clean stale cmake cache from previous failed runs.
  rm -rf "cbuild_engine_${or_arch}_ompi"
  ./build_script.sh -arch="${or_arch}" -release -mpi=ompi \
    -no-python -nt="${CPU_COUNT}"
)

# Install executables (use a glob in case the engine has an MPI suffix).
mkdir -p "${PREFIX}/bin"
for f in exec/starter_${or_arch}*; do
  [ -f "$f" ] && install -m 0755 "$f" "${PREFIX}/bin/$(basename "$f")" && break
done
for f in exec/engine_${or_arch}*; do
  [ -f "$f" ] && install -m 0755 "$f" "${PREFIX}/bin/engine_${or_arch}" && break
done

# Ship the prebuilt shared libs the Starter links against (Apache APR + the
# HyperMesh reader) and point the binaries' rpath at $PREFIX/lib so the conda
# runtime (libgfortran/libgomp/libstdc++) and these bundled libs are found
# without LD_LIBRARY_PATH (upstream's CMake flags drop the toolchain LDFLAGS).
mkdir -p "${PREFIX}/lib"
for lib in "libhm_reader_${extlib_arch}.so" libapr-1.so libapr-1.so.0; do
  install -m 0755 "extlib/hm_reader/${extlib_arch}/${lib}" "${PREFIX}/lib/"
done
# Fix the rpath of every installed binary (upstream CMake drops LDFLAGS).
# The arch suffix varies per platform (e.g. linux64_gf vs linuxa64_gf).
for f in "${PREFIX}/bin/starter_${or_arch}"*; do
  [ -f "$f" ] && patchelf --set-rpath '$ORIGIN/../lib' "$f"
done
for f in "${PREFIX}/bin/engine_${or_arch}"*; do
  [ -f "$f" ] && patchelf --set-rpath '$ORIGIN/../lib' "$f"
done

# Install license file for rattler-build (it looks for license_file
# relative to the work root, but our source is nested in openradioss/).
cp "${SRC_DIR}/openradioss/LICENSE.md" "${SRC_DIR}/LICENSE.md"