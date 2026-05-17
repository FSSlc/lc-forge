@echo on

go build -v -o "%PREFIX%\bin\go-licenses.exe" ^
    || exit 2

"%PREFIX%\bin\go-licenses.exe" save . --save_path=license-files ^
    || exit 3
