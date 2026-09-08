nmake triangle
nmake trilibrary
mkdir %LIBRARY_BIN%
copy triangle.exe %LIBRARY_BIN%
mkdir %LIBRARY_LIB%
copy libtri.lib %LIBRARY_LIB%
mkdir -p %LIBRARY_INC%
copy triangle.h %LIBRARY_INC%
