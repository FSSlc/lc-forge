#!/bin/bash
set -Eeuo pipefail

# The third-party libraries are fetched into $SRC_DIR/extlib by rattler-build;
# land them inside the source tree where load_extlib.py expects (../extlib
# relative to starter/ and engine/).  With extlib/EXTLIB_VERSION.json in place
# the loader matches the requested version and never downloads.
rm -rf "${SRC_DIR}/openradioss/extlib"
mv "${SRC_DIR}/extlib" "${SRC_DIR}/openradioss/extlib"

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

# Starter and Engine, SMP gfortran build (-release), without Python linking.
# MPI is left out: upstream only supports -mpi=ompi and scns has mpich only.
(
  cd starter
  ./build_script.sh -arch="${or_arch}" -release -no-python -nt="${CPU_COUNT}"
)
(
  cd engine
  ./build_script.sh -arch="${or_arch}" -release -no-python -nt="${CPU_COUNT}"
)

# Install executables.
mkdir -p "${PREFIX}/bin"
install -m 0755 "exec/starter_${or_arch}" "${PREFIX}/bin/"
install -m 0755 "exec/engine_${or_arch}" "${PREFIX}/bin/"

# Ship the prebuilt shared libs the Starter links against (Apache APR + the
# HyperMesh reader) and point the binaries' rpath at $PREFIX/lib so the conda
# runtime (libgfortran/libgomp/libstdc++) and these bundled libs are found
# without LD_LIBRARY_PATH (upstream's CMake flags drop the toolchain LDFLAGS).
mkdir -p "${PREFIX}/lib"
for lib in "libhm_reader_${extlib_arch}.so" libapr-1.so libapr-1.so.0; do
  install -m 0755 "extlib/hm_reader/${extlib_arch}/${lib}" "${PREFIX}/lib/"
done
patchelf --set-rpath '$ORIGIN/../lib' "${PREFIX}/bin/starter_${or_arch}"
patchelf --set-rpath '$ORIGIN/../lib' "${PREFIX}/bin/engine_${or_arch}"