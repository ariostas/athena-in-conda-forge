#!/bin/bash
set -euxo pipefail

# The base project of the Athena layers: atlasexternals' AthenaExternals project with no LCG
# release (LCG 0) and none of its bundled externals (they come from conda-forge and from the
# recipes next to this one). What it installs is the project configuration, the Pre- and
# PostConfig files, AtlasCMake and AtlasLCG, and the setup scripts, in the CVMFS layout that
# the Athena layers expect for their base projects:
#   ${PREFIX}/opt/athena/AthenaExternals/<version>/InstallArea/<platform>
case "${target_platform}" in
  linux-64)      ARCH=x86_64 ;;
  linux-aarch64) ARCH=aarch64 ;;
  *) echo "Unsupported platform ${target_platform}"; exit 1 ;;
esac
# The name AtlasCMake would choose itself, with the "cf" OS name of patch 0001.
PLATFORM=${ARCH}-cf-gcc$(${CXX} -dumpversion | cut -d. -f1)-opt
INSTALL=${PREFIX}/opt/athena/AthenaExternals/${PKG_VERSION}/InstallArea/${PLATFORM}

printf -- '- .*\n' > package_filters.txt
cmake -S Projects/AthenaExternals -B build -G Ninja ${CMAKE_ARGS} \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${INSTALL}" \
  -DCMAKE_PROJECT_VERSION="${PKG_VERSION}" \
  -DATLAS_FORCE_PLATFORM="${PLATFORM}" \
  -DLCG_VERSION_NUMBER=0 -DLCG_VERSION_POSTFIX="" \
  -DATLAS_PACKAGE_FILTER_FILE="${PWD}/package_filters.txt"
cmake --build build
cmake --install build

# The Find modules of the externals that AthenaExternals would build itself (Gaudi, yampl,
# ...): it only installs the module of a package it builds, and here they come from conda.
# ATLAS's FindGaudi wraps Gaudi's own configuration, and creates the plain "GaudiKernel"
# target that Athena packages link against.
cp External/*/cmake/Find*.cmake "${INSTALL}/cmake/modules/"
# Replacements for AtlasLCG modules that do not work with conda-forge packages.
cp "${RECIPE_DIR}"/cmake/Find*.cmake "${INSTALL}/cmake/modules/"
# Settings for every project built on top of this one.
cat "${RECIPE_DIR}/cmake/conda-postconfig.cmake" >> "${INSTALL}/cmake/PostConfig.cmake"
