#!/usr/bin/env bash

set -o xtrace -o nounset -o pipefail -o errexit

export CARGO_PROFILE_RELEASE_STRIP=symbols
export CARGO_PROFILE_RELEASE_LTO=fat

export OPENSSL_DIR=${PREFIX}
export OPENSSL_NO_VENDOR=1

# check licenses
cargo-bundle-licenses \
    --format yaml \
    --output THIRDPARTY.yml

# build statically linked binary with Rust
cargo install --no-track --locked --root ${PREFIX} --bin jj --path cli

if [[ ${build_platform} == ${target_platform} ]]; then
    mkdir -p ${PREFIX}/share/fish/vendor_completions.d
    mkdir -p ${PREFIX}/share/zsh/site-functions
    jj util completion zsh > ${PREFIX}/share/zsh/site-functions/_jj
    jj util completion fish > ${PREFIX}/share/fish/vendor_completions.d/jj.fish
    mkdir -p ${PREFIX}/share/man/man1
    jj util install-man-pages ${PREFIX}/share/man/man1
fi
