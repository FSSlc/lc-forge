
call cmake -G "%CMAKE_GENERATOR%" -D CMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% -D CMAKE_BUILD_TYPE=Release -D LIBRARY_INC=%LIBRARY_INC% .
if errorlevel 1 exit 1

call cmake --build . --target install --config Release
if errorlevel 1 exit 1
