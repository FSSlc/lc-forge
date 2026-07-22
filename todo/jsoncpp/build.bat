set CMAKE_CONFIG=Release

cmake -LAH %CMAKE_ARGS% -G Ninja ^
  -DCMAKE_BUILD_TYPE="%CMAKE_CONFIG%" ^
  -DBUILD_SHARED_LIBS=ON ^
  -DBUILD_STATIC_LIBS=OFF ^
  -DPYTHON_EXECUTABLE="%PYTHON%" ^
  -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF ^
  -DCMAKE_CXX_STANDARD=17 ^
  -DCMAKE_CXX_STANDARD_REQUIRED=ON ^
  -B build .
if errorlevel 1 exit 1

cmake --build build --config %CMAKE_CONFIG% --target install
if errorlevel 1 exit 1

ctest --test-dir build --output-on-failure
if errorlevel 1 exit 1
