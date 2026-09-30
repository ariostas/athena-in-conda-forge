cmake_minimum_required(VERSION 3.20)
project(geomodel_test LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
find_package(GeoModelCore REQUIRED)
find_package(GeoModelIO REQUIRED)
add_executable(write_read write_read.cxx)
target_link_libraries(write_read GeoModelCore::GeoModelKernel GeoModelIO::GeoModelIOHelpers
  GeoModelIO::GeoModelDBManager)
