md out\release
if errorlevel 1 exit 1
cd out\release
if errorlevel 1 exit 1
cmake ^
    -GNinja ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DDOCTEST_WITH_TESTS=OFF ^
    -DDOCTEST_WITH_MAIN_IN_STATIC_LIB=OFF ^
    ..\..
if errorlevel 1 exit 1
ninja install
if errorlevel 1 exit 1
