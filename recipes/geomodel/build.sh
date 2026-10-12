#!/bin/bash
set -euxo pipefail

# On macOS conda-forge's libc++ headers mark library features newer than the deployment target
# as unavailable (some, such as the time zone database, even from inline code that <chrono>
# brings in). The environments have conda-forge's own, current libc++ at run time.
if [[ "${target_platform}" == osx-* ]]; then
  export CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
fi

# GeoModel's CMake turns warnings into errors (CMAKE_COMPILE_WARNING_AS_ERROR), which a newer
# compiler than upstream's CI can trip.
cmake -S . -B build -G Ninja ${CMAKE_ARGS} -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
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
