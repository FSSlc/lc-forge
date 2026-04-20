set -o xtrace -o nounset -o pipefail -o errexit

if [[ "$build_platform" == "linux-64" ]]; then
  # The x86 cross-compiler doesn't know about -mtune=powerX, it does know about -mcpu=powerX
  CFLAGS=$(echo "$CFLAGS" | sed -E 's/-mtune=power[0-9]+\s*| \s*-mtune=power[0-9]+//g')
fi

# Required for cross-compiling with pkg-config
export PKG_CONFIG_SYSROOT_DIR=$PREFIX
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
export CARGO_BUILD_RUSTFLAGS="$CARGO_BUILD_RUSTFLAGS -L all=$PREFIX/lib"

if [[ "$c_compiler" == "clang" ]]; then
  echo "-L$BUILD_PREFIX/lib -Wl,-rpath,$BUILD_PREFIX/lib" > $BUILD_PREFIX/bin/$BUILD.cfg
  echo "-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib" > $BUILD_PREFIX/bin/$HOST.cfg
fi

# build statically linked binary with Rust
cargo install --path . --root ${PREFIX} --verbose --locked

cargo-bundle-licenses --format yaml --output THIRDPARTY.yml

# strip debug symbols
"$STRIP" "$PREFIX/bin/cargo-cinstall"
"$STRIP" "$PREFIX/bin/cargo-cbuild"
"$STRIP" "$PREFIX/bin/cargo-ctest"
"$STRIP" "$PREFIX/bin/cargo-capi"

# remove extra build file
rm -f "${PREFIX}/.crates.toml"
