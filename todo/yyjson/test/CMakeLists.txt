cmake_minimum_required(VERSION 3.16)

project(test-yyjson LANGUAGES C)

find_package(yyjson CONFIG REQUIRED)

add_executable(test_yyjson test.c)
target_link_libraries(test_yyjson PRIVATE yyjson::yyjson)
