@echo ON
setlocal enabledelayedexpansion

mkdir build
cd build

cmake -LAH -G "Ninja"                          ^
    %CMAKE_ARGS%                               ^
    -DCMAKE_BUILD_TYPE="Release"               ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX%    ^
    -DCMAKE_PREFIX_PATH=%LIBRARY_PREFIX%       ^
    -DBUILD_SHARED_LIBS=1                      ^
    -DBUILD_STATIC_LIBS=OFF                    ^
    -DBUILD_SHARED_LIBS=ON                     ^
    ..
if errorlevel 1 exit 1

ninja install
if errorlevel 1 exit 1
