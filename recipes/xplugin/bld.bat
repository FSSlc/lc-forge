md build
if errorlevel 1 exit 1
cd build
if errorlevel 1 exit 1
cmake ^
    -GNinja ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DXPLUGIN_BUILD_TESTS=ON ^
    -DXPLUGIN_BUILD_EXAMPLES=ON ^
    -DXPLUGIN_BUILD_DOCS=OFF ^
    -DCMAKE_PREFIX_PATH="%PREFIX%\Library" ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    ..

if errorlevel 1 exit 1
ninja install
if errorlevel 1 exit 1
