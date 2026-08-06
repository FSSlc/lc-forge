cmake_minimum_required(VERSION 3.23)

project(rfl_test LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(reflectcpp REQUIRED)

add_executable(rfl_test test.cpp)
target_link_libraries(rfl_test PRIVATE reflectcpp::reflectcpp)
