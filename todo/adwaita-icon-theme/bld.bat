@echo on

meson setup builddir --buildtype=release --prefix="%LIBRARY_PREFIX%"
if %ERRORLEVEL% neq 0 exit 1

:: print results of build configuration
meson configure builddir
if %ERRORLEVEL% neq 0 exit 1

meson install -C builddir
if %ERRORLEVEL% neq 0 exit 1
