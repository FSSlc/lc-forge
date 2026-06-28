@echo on

mkdir build
cd build
cmake %CMAKE_ARGS% ^
    -G "Ninja" ^
    %SRC_DIR% ^
    -DUSE_MATCHCOMPILER=ON ^
    -DFILESDIR=%PREFIX%/share/Cppcheck ^
    -DUSE_BUNDLED_TINYXML2=OFF ^
    -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON

if errorlevel 1 exit 1
ninja install
if errorlevel 1 exit 1
cd ..
set "SETUPTOOLS_SCM_PRETEND_VERSION=%PKG_VERSION%"
%PREFIX%\python.exe -m pip install htmlreport\ --no-deps -vv
