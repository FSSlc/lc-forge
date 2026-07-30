@echo on
SetLocal EnableDelayedExpansion

set V_MAJOR=20260526

if [%PKG_NAME%] == [libabseil] (
    REM windows-only (almost-)all-in-one DLL + import library
    if not exist %LIBRARY_BIN%\abseil_dll.dll exit 1
    if not exist %LIBRARY_LIB%\abseil_dll.lib exit 1
    REM absence of test targets in regular abseil output
    if exist %LIBRARY_BIN%\abseil_test_dll.dll exit 1
    if exist %LIBRARY_LIB%\abseil_test_dll.lib exit 1

    REM shared libs: some remain static on windows
    REM always static on win
    if not exist %LIBRARY_LIB%\absl_decode_rust_punycode.lib exit 1
    if not exist %LIBRARY_LIB%\absl_demangle_rust.lib exit 1
    if not exist %LIBRARY_LIB%\absl_flags_commandlineflag.lib exit 1
    if not exist %LIBRARY_LIB%\absl_flags_config.lib exit 1
    if not exist %LIBRARY_LIB%\absl_flags_marshalling.lib exit 1
    if not exist %LIBRARY_LIB%\absl_flags_parse.lib exit 1
    if not exist %LIBRARY_LIB%\absl_flags_private_handle_accessor.lib exit 1
    if not exist %LIBRARY_LIB%\absl_flags_program_name.lib exit 1
    if not exist %LIBRARY_LIB%\absl_flags_reflection.lib exit 1
    if not exist %LIBRARY_LIB%\absl_flags_usage.lib exit 1
    if not exist %LIBRARY_LIB%\absl_hashtable_profiler.lib exit 1
    if not exist %LIBRARY_LIB%\absl_log_flags.lib exit 1
    if not exist %LIBRARY_LIB%\absl_poison.lib exit 1
    if not exist %LIBRARY_LIB%\absl_profile_builder.lib exit 1

    REM shared on win (via abseil_dll)
    if exist %LIBRARY_LIB%\absl_base.lib exit 1
    if exist %LIBRARY_LIB%\absl_civil_time.lib exit 1
    if exist %LIBRARY_LIB%\absl_crc_cord_state.lib exit 1
    if exist %LIBRARY_LIB%\absl_crc_cpu_detect.lib exit 1
    if exist %LIBRARY_LIB%\absl_crc32c.lib exit 1
    if exist %LIBRARY_LIB%\absl_cord.lib exit 1
    if exist %LIBRARY_LIB%\absl_cordz_functions.lib exit 1
    if exist %LIBRARY_LIB%\absl_cordz_handle.lib exit 1
    if exist %LIBRARY_LIB%\absl_cordz_info.lib exit 1
    if exist %LIBRARY_LIB%\absl_cordz_sample_token.lib exit 1
    if exist %LIBRARY_LIB%\absl_die_if_null.lib exit 1
    if exist %LIBRARY_LIB%\absl_examine_stack.lib exit 1
    if exist %LIBRARY_LIB%\absl_exponential_biased.lib exit 1
    if exist %LIBRARY_LIB%\absl_failure_signal_handler.lib exit 1
    if exist %LIBRARY_LIB%\absl_hash.lib exit 1
    if exist %LIBRARY_LIB%\absl_hashtablez_sampler.lib exit 1
    if exist %LIBRARY_LIB%\absl_int128.lib exit 1
    if exist %LIBRARY_LIB%\absl_log_severity.lib exit 1
    if exist %LIBRARY_LIB%\absl_periodic_sampler.lib exit 1
    if exist %LIBRARY_LIB%\absl_random_distributions.lib exit 1
    if exist %LIBRARY_LIB%\absl_random_seed_gen_exception.lib exit 1
    if exist %LIBRARY_LIB%\absl_random_seed_sequences.lib exit 1
    if exist %LIBRARY_LIB%\absl_raw_hash_set.lib exit 1
    if exist %LIBRARY_LIB%\absl_scoped_set_env.lib exit 1
    if exist %LIBRARY_LIB%\absl_spinlock_wait.lib exit 1
    if exist %LIBRARY_LIB%\absl_stacktrace.lib exit 1
    if exist %LIBRARY_LIB%\absl_status.lib exit 1
    if exist %LIBRARY_LIB%\absl_statusor.lib exit 1
    if exist %LIBRARY_LIB%\absl_strerror.lib exit 1
    if exist %LIBRARY_LIB%\absl_strings.lib exit 1
    if exist %LIBRARY_LIB%\absl_symbolize.lib exit 1
    if exist %LIBRARY_LIB%\absl_synchronization.lib exit 1
    if exist %LIBRARY_LIB%\absl_throw_delegate.lib exit 1
    if exist %LIBRARY_LIB%\absl_time.lib exit 1
    if exist %LIBRARY_LIB%\absl_time_zone.lib exit 1

    REM absence of test targets
    if exist %LIBRARY_LIB%\absl_scoped_mock_log.lib exit 1

    REM pkg-config abseil_dll
    pkg-config --print-errors --exact-version %V_MAJOR% abseil_dll
)

if [%PKG_NAME%] == [libabseil-tests] (
    if not exist %LIBRARY_BIN%\abseil_test_dll.dll exit 1
    if not exist %LIBRARY_LIB%\abseil_test_dll.lib exit 1
    if not exist %LIBRARY_LIB%\absl_scoped_mock_log.lib exit 1
    pkg-config --print-errors --exact-version %V_MAJOR% absl_scoped_mock_log
    pkg-config --print-errors --exact-version %V_MAJOR% abseil_test_dll
)

REM CMake integration test
cd cmake_test
set "CMAKE_ARGS=%CMAKE_ARGS% -GNinja -DCMAKE_BUILD_TYPE=Release"

if [%PKG_NAME%] == [libabseil-tests] (
    set TRY_TEST_TARGET=1
)

cmake %CMAKE_ARGS% -DCMAKE_CXX_STANDARD=17 .
if %ERRORLEVEL% neq 0 exit 1

cmake --build .
if %ERRORLEVEL% neq 0 exit 1

flags_example.exe
if %ERRORLEVEL% neq 0 exit 1