cmake_minimum_required(VERSION 3.10)
project(mpl_recipe_test LANGUAGES CXX)

# Verifies the installed CMake package (mplConfig.cmake / mplTargets.cmake)
# and that the header-only C++17 interface links against MPI.
find_package(mpl REQUIRED)

add_executable(mpl_hello hello.cc)
target_link_libraries(mpl_hello PRIVATE mpl::mpl)
