#!/usr/bin/env bash

set -o xtrace -o nounset -o pipefail -o errexit

if [[ ${CONDA_BUILD_CROSS_COMPILATION:-0} == 1 ]]; then
    echo gl_cv_func_strcasecmp_works=yes > ${SRC_DIR}/config.site
    export CONFIG_SITE=${SRC_DIR}/config.site
fi

./configure --prefix=${PREFIX} \
    --libdir=${PREFIX}/lib \
    --build=${BUILD} \
    --host=${HOST} || cat config.log

make -j ${CPU_COUNT}
make install
make installcheck
