#!/usr/bin/env bash

export CARGO_HOME=${CARGO_HOME:-${CONDA_PREFIX}/.cargo}
export CARGO_CONFIG=${CARGO_CONFIG:-${CARGO_HOME}/config}
export RUSTUP_HOME=${RUSTUP_HOME:-${CARGO_HOME}/rustup}

[[ -d ${CARGO_HOME} ]] || mkdir -p ${CARGO_HOME}

export CARGO_TARGET_@rust_arch_env_build@_LINKER=${CC_FOR_BUILD:-${CONDA_PREFIX}/bin/@rust_default_cc_build@}
export CARGO_TARGET_@rust_arch_env@_LINKER=${CC:-${CONDA_PREFIX}/bin/@rust_default_cc@}
export CARGO_BUILD_TARGET=@rust_arch@
export CONDA_RUST_HOST=@rust_arch_env_build@
export CONDA_RUST_TARGET=@rust_arch_env@
export PKG_CONFIG_PATH_@rust_arch_env_build@=${CONDA_PREFIX}/lib/pkgconfig
export PKG_CONFIG_PATH_@rust_arch_env@=${PREFIX:-${CONDA_PREFIX}}/lib/pkgconfig

export CC_@CONDA_RUST_HOST_LOWER@="${CC_FOR_BUILD:-${CONDA_PREFIX}/bin/@rust_default_cc_build@}"
export CFLAGS_@CONDA_RUST_HOST_LOWER@="-isystem ${CONDA_PREFIX}/include"
export CFLAGS_@CONDA_RUST_TARGET_LOWER@="${CFLAGS}"
export CPPFLAGS_@CONDA_RUST_HOST_LOWER@="-isystem ${CONDA_PREFIX}/include"
export CPPFLAGS_@CONDA_RUST_TARGET_LOWER@="${CPPFLAGS}"
export CXXFLAGS_@CONDA_RUST_HOST_LOWER@="-isystem ${CONDA_PREFIX}/include"
export CXXFLAGS_@CONDA_RUST_TARGET_LOWER@="${CXXFLAGS}"

if [[ "@cross_target_platform@" == linux*  ]]; then
  export CARGO_BUILD_RUSTFLAGS="-C link-arg=-Wl,-rpath-link,${PREFIX:-${CONDA_PREFIX}}/lib -C link-arg=-Wl,-rpath,${PREFIX:-${CONDA_PREFIX}}/lib"
elif [[ "@cross_target_platform@" == win* ]]; then
  export CARGO_TARGET_@rust_arch_env@_LINKER=${CONDA_PREFIX}/bin/lld-link

  # some rust crates need a linux gnu c compiler at buildtime
  # thus we need to create custom cflags since the default ones are for clang
  export AR_@CONDA_RUST_HOST_LOWER@="${AR}"
  export AR_@CONDA_RUST_TARGET_LOWER@=$CONDA_PREFIX/bin/llvm-lib

  export CC_@CONDA_RUST_TARGET_LOWER@=$CONDA_PREFIX/bin/clang-cl
  export CXX_@CONDA_RUST_TARGET_LOWER@=$CONDA_PREFIX/bin/clang-cl

  export LDFLAGS="$LDFLAGS -manifest:no"

  # Setup CMake Toolchain
  export CMAKE_GENERATOR=Ninja
elif [[ "@cross_target_platform@" == osx* ]]; then
  export CARGO_BUILD_RUSTFLAGS="-C link-arg=-Wl,-rpath,${PREFIX:-${CONDA_PREFIX}}/lib"
  if [[ "${CONDA_BUILD:-}" != "" ]]; then
    export CARGO_BUILD_RUSTFLAGS="$CARGO_BUILD_RUSTFLAGS -C link-arg=-Wl,-headerpad_max_install_names -C link-arg=-Wl,-dead_strip_dylibs"
  fi
fi

export PATH=${CARGO_HOME}/bin:${PATH}

# cross compiling for unix platforms
if [[ "@cross_target_platform@" == osx* || "@cross_target_platform@" == linux* ]]; then
  if [[ "@CONDA_RUST_HOST_LOWER@" != "@CONDA_RUST_TARGET_LOWER@" ]]; then
    # when cross compiling we must set `CARGO_TARGET_$rust_arch_env_build_RUSTFLAGS`
    export CARGO_TARGET_@rust_arch_env_build@_RUSTFLAGS="-C link-arg=-Wl,-rpath,${BUILD_PREFIX:-${CONDA_PREFIX}}/lib"
  fi
fi
