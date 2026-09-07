mkdir "%SRC_DIR%"\build
pushd "%SRC_DIR%"\build

REM This also sets the minimum CMake policy version to 3.5 for compatibility. Can be removed with >2.14.1

cmake -G "Ninja" ^
      -DBUILD_SHARED_LIBS=ON ^
      -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ^
      ..
if errorlevel 1 exit 1

cmake --build . --target install --config Release
if errorlevel 1 exit 1
