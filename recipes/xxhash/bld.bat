mkdir build
cd build
cmake %CMAKE_ARGS% ../cmake_unofficial ^
      -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
      -DBUILD_SHARED_LIBS=ON ^
      -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
cmake --build . --target install --config Release
