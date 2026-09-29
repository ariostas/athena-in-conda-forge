# The tdaq-common subset of this recipe, as one project (see TDAQShim.cmake).
cmake_minimum_required(VERSION 3.26)
project(tdaq-common VERSION 14.0.0 LANGUAGES C CXX)

# ers builds standalone unless it is part of a tdaq project.
set(TDAQ_PROJECT_NAME tdaq-common)
# test, benchmark and debugging programs that are installed by tdaq
set(TDAQ_SKIP_EXECUTABLES
  "^(Circ.*|test.*|readData|readMetaData|FileConverter|ers_receiver|adler32mt_threshold)$"
  CACHE STRING "")
include(TDAQShim.cmake)
# CTPfragment's generator is run with PYTHONHOME set to this.
get_filename_component(Python_ROOT_DIR "${Python_EXECUTABLE}" DIRECTORY)
get_filename_component(Python_ROOT_DIR "${Python_ROOT_DIR}" DIRECTORY)

foreach(pkg ers compression eformat EventStorage CTPfragment hltinterface MuCalDecode circ)
  add_subdirectory(${pkg})
endforeach()

# CTPfragment's sources include the header it generates.
add_dependencies(CTPfragment generate_CTPdataformatVersion)
