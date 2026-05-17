#!/usr/bin/env bash
set -exuf

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" == "1" && "${CMAKE_CROSSCOMPILING_EMULATOR:-}" == "" ]]; then
  # This is currently only true on osx-arm64
  exit 0
fi

# Test variable is set
test "${CONDA_GO_COMPILER}" == 1


# Test GOBIN is set to $PREFIX/bin
test "$(go env GOBIN)" == "$CONDA_PREFIX/bin"


# Test GOPATH is set to SRC-DIR
# We cannot use that here though as conda-build checks for
# the existence of SRC-DIR for an old behaviour change.
test "$(go env GOPATH)" == "${PWD}/gopath"


# Print diagnostics
go env

go mod init example.com/hello_world
go build -buildvcs=false .
if [[ "${cross_target_platform}" == "${build_platform}" || "${CMAKE_CROSSCOMPILING_EMULATOR:-}" != "" ]]; then
  ./hello_world
fi
