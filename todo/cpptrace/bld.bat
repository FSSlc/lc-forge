cmake %CMAKE_ARGS% -S . -B build -DBUILD_SHARED_LIBS=On -DCMAKE_PREFIX_PATH=%PREFIX%
cmake --build build --config Release --target install
