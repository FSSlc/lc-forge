#!/usr/bin/env bash

set -Eeuo pipefail

sysroot="${CONDA_BUILD_SYSROOT:-}"
if [[ -z "${sysroot}" || ! -d "${sysroot}" ]]; then
  echo "error: CONDA_BUILD_SYSROOT must point to an existing sysroot" >&2
  exit 1
fi

case "${target_platform}" in
  linux-64)
    sys_libdir="usr/lib64"
    sys_lddir="lib64"
    loader="ld-linux-x86-64.so.2"
    ;;
  linux-aarch64)
    sys_libdir="usr/lib"
    sys_lddir="lib"
    loader="ld-linux-aarch64.so.1"
    ;;
  *)
    echo "error: unsupported target_platform ${target_platform}" >&2
    exit 1
    ;;
esac

mkdir -p build
cd build

cfg_args=(
  --prefix="${PREFIX}"
  --cc="${CC}"
  --ar="${AR}"
  --disable-static
  # {B} expands at runtime to tcc's private lib dir ($PREFIX/lib/tcc), so
  # the crt objects, headers and runtime libraries bundled below are found
  # from any prefix without baking build-time sysroot paths into the binaries.
  --crtprefix='{B}'
  --libpaths='{B}'
  --sysincludepaths='{B}/include:{B}/include/glibc:/usr/include:/usr/local/include'
)

case "${target_platform}" in
  linux-64 | osx-64)
    cfg_args+=(--cpu=x86_64)
    ;;
  linux-aarch64 | osx-arm64)
    cfg_args+=(--cpu=aarch64)
    ;;
esac

if [[ "${target_platform}" == linux-* ]]; then
  # mmap-based executable memory for `tcc -run`
  cfg_args+=(--with-selinux)
fi

# Ship the glibc headers next to the bundled runtime. The bootstrap tcc also
# needs them to compile bcheck.c (glibc >= 2.34 removed __malloc_hook, so the
# host headers can't be used).
cp -a "${sysroot}/usr/include" "${SRC_DIR}/include/glibc"

../configure "${cfg_args[@]}"
make -j"${CPU_COUNT}"
make install

# Bundle a self-contained C runtime next to libtcc1.a. tcc resolves {B}
# against its relocated install dir, so the package works from any prefix.
tcc_lib="${PREFIX}/lib/tcc"
sysroot_lib="${sysroot}/${sys_libdir}"
sysroot_ld="${sysroot}/${sys_lddir}"

cp -a "${sysroot}/usr/include" "${tcc_lib}/include/glibc"

install -m 0644 \
  "${sysroot_lib}/crt1.o" \
  "${sysroot_lib}/crti.o" \
  "${sysroot_lib}/crtn.o" \
  "${tcc_lib}/"

for lib in libc libm libpthread libdl librt libutil; do
  if [[ -e "${sysroot_lib}/${lib}.so" ]]; then
    cp -L "${sysroot_lib}/${lib}.so" "${tcc_lib}/"
  fi
  cp -L "${sysroot_ld}"/${lib}.so.* "${tcc_lib}/"
  if [[ -e "${sysroot_lib}/${lib}_nonshared.a" ]]; then
    install -m 0644 "${sysroot_lib}/${lib}_nonshared.a" "${tcc_lib}/"
  fi
done

# libc.so.6 has DT_NEEDED on the dynamic loader, which tcc resolves through
# its library search paths when linking.
cp -L "${sysroot_ld}/${loader}" "${tcc_lib}/"

glibc_license="$(echo "${sysroot}"/usr/share/doc/glibc-*/COPYING.LIB)"
install -D -m 0644 "${glibc_license}" \
  "${PREFIX}/share/licenses/${PKG_NAME}/glibc-COPYING.LIB"
