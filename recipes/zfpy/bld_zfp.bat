setlocal EnableDelayedExpansion

:: Make a build folder and change to it.
mkdir build
cd build

:: Configure using the CMakeFiles
cmake -G "Ninja"                               ^
  -DBUILD_ZFPY=OFF                             ^
  -DBUILD_UTILITIES=ON                         ^
  -DBUILD_CFP=ON                               ^
  -DZFP_WITH_OPENMP=ON                         ^
  -DCMAKE_BUILD_TYPE:STRING=Release            ^
  -DPYTHON_INCLUDE_DIR:PATH="%PREFIX%\include" ^
  -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%"    ^
  ..

if errorlevel 1 exit 1

ninja install
if errorlevel 1 exit 1

:: Run tests
ctest
if errorlevel 1 exit 1
bin\testzfp.exe
if errorlevel 1 exit 1
