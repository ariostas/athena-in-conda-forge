cmake_minimum_required(VERSION 3.20)
project(acts_test LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 23)
# the components Athena uses
find_package(Acts REQUIRED COMPONENTS Core Fatras PluginJson PluginGeoModel PluginRoot)
add_executable(acts_test acts_test.cxx)
target_link_libraries(acts_test Acts::Core Acts::PluginJson Acts::PluginGeoModel Acts::PluginRoot
  ActsFatras)
