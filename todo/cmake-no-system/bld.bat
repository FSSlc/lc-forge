set PATH=%CD%\cmake-%PKG_VERSION%-windows\bin;%PATH%

cmake --version
if errorlevel 1 exit 1

cmake -LAH -G Ninja                                          ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%"                   ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%"                ^
    -DCMAKE_CXX_STANDARD:STRING=17                           ^
    -DCURL_USE_SCHANNEL:BOOL=ON                              ^
    -DCURL_WINDOWS_SSPI:BOOL=ON                              ^
    -DBUILD_CursesDialog:BOOL=ON                             ^
    .
if errorlevel 1 exit 1

cmake --build . --target install -j%CPU_COUNT%
if errorlevel 1 exit 1
