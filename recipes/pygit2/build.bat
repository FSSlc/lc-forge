@echo on
set LIBGIT2=%LIBRARY_PREFIX%
python -m pip install --no-deps --ignore-installed .
if errorlevel 1 exit 1
