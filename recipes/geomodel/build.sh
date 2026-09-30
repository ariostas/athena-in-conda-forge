#!/bin/bash
set -euxo pipefail

# GeoModel's CMake turns warnings into errors (CMAKE_COMPILE_WARNING_AS_ERROR), which a newer
# compiler than upstream's CI can trip.
cmake -S . -B build -G Ninja ${CMAKE_ARGS} \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF \
  -DGEOMODEL_BUILD_TOOLS=ON \
  -DGEOMODEL_USE_BUILTIN_EIGEN3=OFF \
  -DGEOMODEL_USE_BUILTIN_JSON=OFF \
  -DGEOMODEL_USE_BUILTIN_XERCESC=OFF
cmake --build build --parallel "${CPU_COUNT}"
cmake --install build
