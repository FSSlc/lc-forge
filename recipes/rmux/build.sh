#!/usr/bin/env bash

set -o xtrace -o nounset -o pipefail -o errexit

export CARGO_PROFILE_RELEASE_STRIP=symbols
export CARGO_PROFILE_RELEASE_LTO=fat

cargo-bundle-licenses \
    --format yaml \
    --output THIRDPARTY.yml

# build statically linked binary with Rust
cargo install --bins --no-track --locked --root ${PREFIX} --path .

# Install man page
mkdir -p ${PREFIX}/share/man/man1
cp rmux.1 ${PREFIX}/share/man/man1/

# Tell `pixi global` to not set CONDA_PREFIX during activation
# https://pixi.sh/dev/global_tools/introduction/#opt-out-of-conda_prefix
mkdir -p "${PREFIX}/etc/pixi/rmux"
touch "${PREFIX}/etc/pixi/rmux/global-ignore-conda-prefix"
