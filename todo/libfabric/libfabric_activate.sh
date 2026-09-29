# rattler-build sets PKG_NAME, not CONDA_BUILD in test env
# ref: https://github.com/prefix-dev/rattler-build/issues/1317
# since this is an activate script, it should run on all shells,
# though only the first `if` really needs to since conda builds are necessarily bash
if [ "${CONDA_BUILD:-}" = "1" ] || [ -n "${PKG_NAME:-}" ]; then
  echo "setting libfabric environment variables for conda-build"
  if [ -z "${FI_PROVIDER:-}" ]; then
    echo "FI_PROVIDER=tcp"
    export FI_PROVIDER=tcp
  fi
fi
