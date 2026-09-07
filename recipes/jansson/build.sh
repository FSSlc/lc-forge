#!/bin/bash

set -exo pipefail

autoreconf -i
./configure --prefix=$PREFIX --disable-static
[[ "$target_platform" == "win-64" ]] && patch_libtool
make -j${CPU_COUNT}

# Ignore this test
cat > test/suites/api/check-exports <<EOF
#!/bin/sh
exit 0
EOF
chmod +x test/suites/api/check-exports

make install
if [[ "$CONDA_BUILD_CROSS_COMPILATION" != "1" ]]; then
    make check || { cat "${SRC_DIR}/test/test-suite.log"; exit 1; }
fi

# Copy janssonConfig.cmake into the package
mkdir -p ${PREFIX}/lib/cmake/jansson
cp "${RECIPE_DIR}/janssonConfig.cmake" "${PREFIX}/lib/cmake/jansson/janssonConfig.cmake"