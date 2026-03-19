#!/bin/bash

set -x

mkdir -p ${PREFIX}/etc/conda/{de,}activate.d
cp "${RECIPE_DIR}"/activate.sh activate.sh
sed -i.bak "s/@rust_arch_env_build@/$rust_arch_env_build/g" activate.sh
sed -i.bak "s/@rust_default_cc_build@/$rust_default_cc_build/g" activate.sh
sed -i.bak "s/@rust_arch@/$rust_arch/g" activate.sh
sed -i.bak "s/@rust_arch_env@/$rust_arch_env/g" activate.sh
sed -i.bak "s/@rust_default_cc@/$rust_default_cc/g" activate.sh
sed -i.bak "s/@cross_target_platform@/$cross_target_platform/g" activate.sh
sed -i.bak "s/@CONDA_RUST_HOST_LOWER@/$(echo $rust_arch_env_build | tr '[:upper:]' '[:lower:]')/g" activate.sh
sed -i.bak "s/@CONDA_RUST_TARGET_LOWER@/$(echo $rust_arch_env | tr '[:upper:]' '[:lower:]')/g" activate.sh
cp activate.sh ${PREFIX}/etc/conda/activate.d/activate_${PKG_NAME}.sh
