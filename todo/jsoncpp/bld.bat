mkdir build && cd build

set CMAKE_CONFIG=Release

rem shared libs fail to build, built static instead
rem https://github.com/open-source-parsers/jsoncpp/issues/631

cmake ^
  -G "NMake Makefiles" ^
  -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
  -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
  -DCMAKE_BUILD_TYPE="%CMAKE_CONFIG%" ^
  -DBUILD_SHARED_LIBS=ON ^
  -DBUILD_STATIC_LIBS=OFF ^
  -DPYTHON_EXECUTABLE="%PYTHON%" ^
  ..
if errorlevel 1 exit 1

cmake --build . --config %CMAKE_CONFIG% --target install
if errorlevel 1 exit 1

ctest --output-on-failure
if errorlevel 1 exit 1
