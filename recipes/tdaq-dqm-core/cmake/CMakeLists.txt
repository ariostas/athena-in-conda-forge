# dqm_core, the data quality monitoring framework of tdaq-common, as one project on the
# replacement for the tdaq build system that the tdaq-common recipe uses (TDAQShim.cmake, a copy
# of that recipe's), with ROOT dictionaries (TDAQRootShim.cmake).
cmake_minimum_required(VERSION 3.26)
project(tdaq-dqm-core VERSION 14.0.0 LANGUAGES C CXX)

set(TDAQ_PROJECT_NAME tdaq-common)
# its test programs
set(TDAQ_SKIP_EXECUTABLES "^dqm_core.*_test$" CACHE STRING "")
include(TDAQShim.cmake)
find_package(Boost REQUIRED CONFIG COMPONENTS thread date_time)
find_package(ROOT REQUIRED COMPONENTS Core RIO Hist)

# ers, from the tdaq-common package
find_library(ERS_LIBRARY NAMES ers REQUIRED)
find_path(ERS_INCLUDE_DIR NAMES ers/ers.h REQUIRED)
add_library(ers SHARED IMPORTED)
set_target_properties(ers PROPERTIES IMPORTED_LOCATION "${ERS_LIBRARY}"
  INTERFACE_INCLUDE_DIRECTORIES "${ERS_INCLUDE_DIR}")

include(TDAQRootShim.cmake)
add_subdirectory(dqm_core)
