cmake_minimum_required(VERSION 3.26)

option(TEST_LIBUNWIND "" OFF)

project(cpptrace-test-program LANGUAGES CXX)
add_executable(program main.cpp)

find_package(cpptrace CONFIG REQUIRED)
target_link_libraries(program PRIVATE cpptrace::cpptrace)

if(TEST_LIBUNWIND)
    target_compile_definitions(program PRIVATE TEST_LIBUNWIND)
endif()
