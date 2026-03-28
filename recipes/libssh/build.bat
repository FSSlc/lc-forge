@echo on
setlocal EnableDelayedExpansion

mkdir build
cd build

:: Configure
cmake -G "Ninja" ^
      -DCMAKE_PREFIX_PATH=%LIBRARY_PREFIX% ^
      -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
      -DCMAKE_BUILD_TYPE=Release ^
      %SRC_DIR%
if errorlevel 1 exit 1

:: Build
cmake --build .  --parallel --target install
if errorlevel 1 exit 1
