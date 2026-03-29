
mkdir build && cd build
cmake -LAH -G"NMake Makefiles" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DBUILD_SHARED_LIBS=ON ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCGNS_ENABLE_HDF5=ON ^
    -DHDF5_NEED_SZIP=OFF ^
    -DHDF5_NEED_ZLIB=ON ^
    -DCGNS_BUILD_CGNSTOOLS=ON ^
    ..
if errorlevel 1 exit 1

cmake --build . --target install --config Release
if errorlevel 1 exit 1
