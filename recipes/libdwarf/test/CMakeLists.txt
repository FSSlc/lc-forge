cmake_minimum_required(VERSION 3.5)
project(test_package LANGUAGES C)

find_package(libdwarf REQUIRED)

add_executable(program test.c)
target_link_libraries(program PRIVATE libdwarf::dwarf)
