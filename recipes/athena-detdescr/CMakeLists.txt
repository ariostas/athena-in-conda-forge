# A layer of Athena, built as its own ATLAS project on top of the previous layer (or on
# AthenaExternals for the first one). Derived from athena's Projects/Athena/CMakeLists.txt.
#
# Configure with:
#   -DATHENA_LAYER_NAME=<project name>        (the top layer is called "Athena")
#   -DATHENA_LAYER_BASE=<base project name>   (AthenaExternals for the first layer)
#   -DATHENA_SOURCE_DIR=<athena checkout>
#   -DATLAS_PACKAGE_FILTER_FILE=<file>        (the packages of this layer)
cmake_minimum_required( VERSION 3.25 )
set( ATHENA_LAYER_VERSION "25.0.73" CACHE STRING "Athena version" )
# Fortran as in Projects/Athena (AthExFortranAlgorithm and a few generator interfaces).
project( ${ATHENA_LAYER_NAME} VERSION ${ATHENA_LAYER_VERSION} LANGUAGES C CXX Fortran )

# No flake8_atlas, cppcheck or CUDA in these builds.
set( ATLAS_FLAKE8 "" CACHE STRING "Default flake8 command" )
set( ATLAS_PYTHON_CHECKER "" CACHE STRING "Python checker command" )
option( ATLAS_USE_CPPCHECK "Use CppCheck in the build" OFF )

# Compiler settings from CxxUtils, taken from the source tree whichever layer builds it.
set( CxxUtilsSettings_DIR "${ATHENA_SOURCE_DIR}/Control/CxxUtils/cmake" )
find_package( CxxUtilsSettings )

find_package( AtlasCMake QUIET )

# The base project(s). The first layer also needs Gaudi and whatever Athena's project file
# finds at the top level; later layers inherit those through the base's PostConfig.
find_package( ${ATHENA_LAYER_BASE} REQUIRED )
if( ATHENA_LAYER_BASE STREQUAL "AthenaExternals" )
   set( _firstLayer TRUE )
   find_package( Gaudi REQUIRED )
   find_package( VDT )
endif()

# Helper CMake code that lives in packages, taken from the source tree.
set( AthenaPoolUtilitiesTest_DIR
   "${ATHENA_SOURCE_DIR}/Database/AthenaPOOL/AthenaPoolUtilities/cmake"
   CACHE PATH "Directory holding the AthenaPoolUtilititesTest module" )
set( xAODUtilities_DIR "${ATHENA_SOURCE_DIR}/Event/xAOD/xAODCore/cmake"
   CACHE PATH "Directory holding the xAODUtilities module" )
set( AtlasGeant4Utilities_DIR "${ATHENA_SOURCE_DIR}/Simulation/AtlasGeant4/cmake"
   CACHE PATH "Directory holding the AtlasGeant4Utilities module" )

list( INSERT CMAKE_MODULE_PATH 0 ${ATHENA_SOURCE_DIR}/Projects/Athena/cmake )

atlas_ctest_setup()

atlas_project( USE ${ATHENA_LAYER_BASE} ${ATHENA_LAYER_VERSION}
   PROJECT_ROOT ${ATHENA_SOURCE_DIR}/ )

# The environment of the externals and of the packages (e.g. CORAL_DBLOOKUP_PATH from
# AtlasAuthentication), for the build and installed: the layer's setup.sh sources it.
lcg_generate_env( SH_FILE ${CMAKE_BINARY_DIR}/${ATLAS_PLATFORM}/env_setup.sh )
# Paths into conda-build's build environment (compilers, cmake) mean nothing at runtime.
set( _replacements )
if( NOT "$ENV{BUILD_PREFIX}" STREQUAL "" )
   list( APPEND _replacements "$ENV{BUILD_PREFIX}" "$ENV{PREFIX}" )
endif()
lcg_generate_env( SH_FILE ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/env_setup_install.sh
   REPLACE ${_replacements} )
install( FILES ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/env_setup_install.sh
   DESTINATION . RENAME env_setup.sh )

# Athena's pre/post-configuration files: settings (C++ standard, externals) that every
# downstream project needs. Installed with the first layer only; the others pick them up
# recursively through their base projects.
if( _firstLayer )
   set( TDAQ_PROJECT_NAME "" )
   set( TDAQ_VERSION "" )
   set( TDAQ_ATROOT "" )
   set( TDAQ-COMMON_VERSION "" )
   set( TDAQ-COMMON_ATROOT "" )
   configure_file( ${ATHENA_SOURCE_DIR}/Projects/Athena/cmake/PreConfig.cmake.in
      ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/PreConfig.cmake @ONLY )
   configure_file( ${ATHENA_SOURCE_DIR}/Projects/Athena/cmake/PostConfig.cmake.in
      ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/PostConfig.cmake @ONLY )
   install( FILES
      ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/PreConfig.cmake
      ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/PostConfig.cmake
      DESTINATION ${CMAKE_INSTALL_CMAKEDIR} )
endif()
