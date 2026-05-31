@echo on

dir %SRC_DIR%\bin

md out\release
if errorlevel 1 exit 1
cd out\release
if errorlevel 1 exit 1
cmake ^
    -GNinja ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DMI_INSTALL_TOPLEVEL=ON ^
    -DMI_BUILD_TESTS=ON ^
    -DMI_BUILD_SHARED=ON  ^
    -DMI_BUILD_STATIC=OFF ^
    -DMI_BUILD_OBJECT=OFF ^
    -DMI_OVERRIDE=OFF ^
    -DMI_LOCAL_DYNAMIC_TLS=ON ^
    ..\..
if errorlevel 1 exit 1
ninja
if errorlevel 1 exit 1
ctest
if errorlevel 1 exit 1
ninja install
if errorlevel 1 exit 1
