mkdir build
cd build

SET GENERATOR=%CMAKE_GENERATOR%

IF "%ARCH%"=="32" (
    SET EXTRA_COMPILE_FLAGS=
) ELSE (
    SET EXTRA_COMPILE_FLAGS=/wd4267 /wd4244
)

REM Check which output we're building
IF "%PKG_NAME%"=="libmsgpack-c-static" (
    SET MSGPACK_BUILD_SHARED_LIBS=OFF
) ELSE (
    SET MSGPACK_BUILD_SHARED_LIBS=ON
)

cmake ^
    -GNinja ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DCMAKE_C_FLAGS="%COMPILE_FLAGS%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DBUILD_SHARED_LIBS=%MSGPACK_BUILD_SHARED_LIBS% ^
    ..
if %errorlevel% neq 0 exit /b %errorlevel%

ninja install
if %errorlevel% neq 0 exit /b %errorlevel%

ctest
ctest --rerun-failed --output-on-failure
if %errorlevel% neq 0 exit /b %errorlevel%
