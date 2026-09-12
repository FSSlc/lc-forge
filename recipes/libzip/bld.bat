@echo on
mkdir build
if errorlevel 1 exit /B 1
cd build
if errorlevel 1 exit /B 1

cmake -G "Ninja" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DENABLE_COMMONCRYPTO=OFF ^
    -DENABLE_GNUTLS=OFF ^
    -DENABLE_MBEDTLS=OFF ^
    -DENABLE_OPENSSL=ON ^
    -DENABLE_WINDOWS_CRYPTO=OFF ^
    -DENABLE_BZIP2=ON ^
    -DENABLE_LZMA=OFF ^
    -DENABLE_ZSTD=OFF ^
    ..
if errorlevel 1 exit /B 1

ctest
if errorlevel 1 exit /B 1

cmake --build . --target install --config Release
if errorlevel 1 exit /B 1
