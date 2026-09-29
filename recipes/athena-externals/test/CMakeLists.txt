# A minimal ATLAS project with one package, built on top of AthenaExternals.
cmake_minimum_required( VERSION 3.25 )
project( HelloProject VERSION 1.0.0 LANGUAGES C CXX )
find_package( AtlasCMake QUIET )
find_package( AthenaExternals REQUIRED )
atlas_project( USE AthenaExternals ${AthenaExternals_VERSION}
   PROJECT_ROOT ${CMAKE_SOURCE_DIR}/ )
