#!/bin/bash
set -euxo pipefail

# Link-time optimization, as ATLAS builds both (Projects/Athena/build_externals.sh:
# ATLAS_GEANT4_USE_LTO, ATLAS_VECGEOM_USE_LTO): AtlasGeant4 links them with LTO, which inlines
# across Geant4's sources and can change floating point results (contractions into fused
# multiply-adds), so this is the build closest to ATLAS's (the simulation still differs from
# ATLAS's release: see athena-sim). Fat objects: the libraries also hold regular code, for
# consumers that link without LTO.
export CFLAGS="${CFLAGS} -flto=auto -ffat-lto-objects"
export CXXFLAGS="${CXXFLAGS} -flto=auto -ffat-lto-objects"

# VecGeom first (atlasexternals' External/VecGeom): static, scalar backend, GDML.
cmake -S vecgeom -B build-vecgeom -G Ninja ${CMAKE_ARGS} \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DCMAKE_CXX_STANDARD=23 \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DBACKEND=Scalar \
  -DGDML=ON \
  -DBUILD_TESTING=OFF
cmake --build build-vecgeom --parallel "${CPU_COUNT}"
cmake --install build-vecgeom

# ATLAS names its multithreaded build "atlasmt" (External/Geant4's patch command).
sed -i 's/geant4.10.6.patch03.atlas15/geant4.10.6.patch03.atlasmt15/g' \
  geant4/source/global/management/include/G4Version.hh \
  geant4/source/run/src/G4RunManagerKernel.cc

# Geant4 with the options of atlasexternals' External/Geant4. The data sets are separate
# conda-forge packages (geant4-data-*), as for conda-forge's geant4. zlib: conda-forge's,
# instead of Geant4's bundled copy.
cmake -S geant4 -B build-geant4 -G Ninja ${CMAKE_ARGS} \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_INSTALL_INCLUDEDIR=include \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DGEANT4_BUILD_CXXSTD=c++23 \
  -DGEANT4_USE_GDML=ON \
  -DGEANT4_USE_SYSTEM_ZLIB=ON \
  -DGEANT4_USE_SYSTEM_EXPAT=ON \
  -DGEANT4_USE_SYSTEM_CLHEP=ON \
  -DGEANT4_USE_SYSTEM_CLHEP_GRANULAR=OFF \
  -DGEANT4_BUILD_MULTITHREADED=ON \
  -DGEANT4_BUILD_TLS_MODEL=global-dynamic \
  -DGEANT4_INSTALL_DATA=OFF \
  -DGEANT4_INSTALL_EXAMPLES=OFF \
  -DGEANT4_INSTALL_PACKAGE_CACHE=OFF \
  -DGEANT4_USE_USOLIDS="CONS;POLYCONE" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_STATIC_LIBS=ON \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build build-geant4 --parallel "${CPU_COUNT}"
cmake --install build-geant4

# geant4make and the environment scripts point at data directories that are not installed
# here: the geant4-data-* packages set the variables.
rm -rf "${PREFIX}/share/Geant4-10.6.3/geant4make" "${PREFIX}/bin/geant4.sh" "${PREFIX}/bin/geant4.csh"
