@echo ON
setlocal enabledelayedexpansion

mkdir "%LIBRARY_PREFIX%\lib\cmake\Glad\"
copy /Y "%SRC_DIR%\cmake\GladConfig.cmake" "%LIBRARY_LIB%\cmake\Glad\GladConfig.cmake"
