#!/bin/bash
set -exuo pipefail

# Shared libraries expected in libabseil
absl_libs=(
    decode_rust_punycode demangle_rust flags_commandlineflag flags_config
    flags_marshalling flags_parse flags_private_handle_accessor flags_program_name
    flags_reflection flags_usage hashtable_profiler log_flags poison profile_builder
    base civil_time crc_cord_state crc_cpu_detect crc32c cord cordz_functions
    cordz_handle cordz_info cordz_sample_token die_if_null examine_stack
    exponential_biased failure_signal_handler hash hashtablez_sampler int128
    log_severity periodic_sampler random_distributions random_seed_gen_exception
    random_seed_sequences raw_hash_set scoped_set_env spinlock_wait stacktrace
    status statusor strerror strings symbolize synchronization throw_delegate
    time time_zone
)

# Test-only libraries (only in libabseil-tests)
absl_test_libs=( scoped_mock_log )

V_MAJOR="20260526"

# --- libabseil tests ---
if [[ "$PKG_NAME" == "libabseil" ]]; then
    for each_lib in "${absl_libs[@]}"; do
        # presence of shared libs
        test -f "$PREFIX/lib/libabsl_${each_lib}${SHLIB_EXT}"
        # absence of static libs
        test ! -f "$PREFIX/lib/libabsl_${each_lib}.a"
        # pkg-config
        pkg-config --print-errors --exact-version "${V_MAJOR}" "absl_${each_lib}"
    done

    for each_lib in "${absl_test_libs[@]}"; do
        # absence of test libs in regular output
        test ! -f "$PREFIX/lib/libabsl_${each_lib}${SHLIB_EXT}"
        test ! -f "$PREFIX/lib/libabsl_${each_lib}.a"
    done
fi

# --- libabseil-tests tests ---
if [[ "$PKG_NAME" == "libabseil-tests" ]]; then
    for each_lib in "${absl_test_libs[@]}"; do
        test -f "$PREFIX/lib/libabsl_${each_lib}${SHLIB_EXT}"
        test ! -f "$PREFIX/lib/libabsl_${each_lib}.a"
        pkg-config --print-errors --exact-version "${V_MAJOR}" "absl_${each_lib}"
    done
fi

# --- CMake integration test (both packages) ---
cd cmake_test
CMAKE_ARGS="${CMAKE_ARGS} -GNinja -DCMAKE_BUILD_TYPE=Release"

if [[ "$PKG_NAME" == "libabseil-tests" ]]; then
    export TRY_TEST_TARGET=1
fi

cmake $CMAKE_ARGS -DCMAKE_CXX_STANDARD=17 .
cmake --build .
./flags_example

if [[ "$PKG_NAME" == "libabseil" ]]; then
    # Check for absence of disturbing SHELL:-Xarch... content in pkg-config files
    if grep -q SHELL "$PREFIX/lib/pkgconfig/absl_random_internal_randen_hwaes.pc"; then
        echo "ERROR: Found SHELL:-Xarch... content in pkg-config file"
        exit 1
    fi
fi