setlocal EnableDelayedExpansion
@echo on

:: meson options
:: (set pkg_config_path so deps in host env can be found)
set ^"MESON_OPTIONS=^
  --prefix="%LIBRARY_PREFIX%" ^
  --pkg-config-path="%LIBRARY_LIB%\pkgconfig;%LIBRARY_PREFIX%\share\pkgconfig" ^
  --wrap-mode=nofallback ^
  --buildtype=release ^
  --backend=ninja ^
   -D docs=false ^
   -D tests=false ^
 ^"

:: configure build using meson
meson setup builddir !MESON_OPTIONS!
if errorlevel 1 exit 1

ninja -v -C builddir
if errorlevel 1 exit 1

ninja -C builddir install
if errorlevel 1 exit 1
