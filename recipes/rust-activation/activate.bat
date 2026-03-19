if not defined CARGO_HOME set CARGO_HOME=%CONDA_PREFIX%\.cargo
if not defined CARGO_CONFIG set CARGO_CONFIG=%CARGO_HOME%\config
if not defined RUSTUP_HOME set RUSTUP_HOME=%CARGO_HOME%\rustup
set PATH=%CARGO_HOME%\bin;%PATH%

if not exist "%CARGO_HOME%" mkdir "%CARGO_HOME%"

if [%LD%] == [] (
    set "CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER=link.exe"
) else (
    set "CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER=%LD%"
)
