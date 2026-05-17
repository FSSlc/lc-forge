#!/usr/bin/env bash
set -eux -o pipefail

go build -v -o "${PREFIX}/bin/go-licenses"

if [[ "${target_platform}" == "osx-arm64" ]]; then
  # Build for osx-64 as this can also be run in cross-compilation mode.
  GOARCH=amd64 go build -v -o go-licenses-native
  ./go-licenses-native save . --save_path=./license-files
else
  go-licenses save . --save_path=./license-files
fi

# TODO: remove if not actually needed, see #6
# rm -r ./license-files/github.com/google/licenseclassifier/licenses

# Make GOPATH directories writeable so conda-build can clean everything up.
CLEAN_GO_PATH=$( go env GOPATH )
export CLEAN_GO_PATH
find "${CLEAN_GO_PATH}" -type d -exec chmod +w {} \;
