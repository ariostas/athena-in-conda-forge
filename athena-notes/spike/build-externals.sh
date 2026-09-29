#!/bin/bash
# Build atlasexternals' AthenaExternals project with no LCG release (LCG 0) and no bundled
# externals: everything comes from the conda env. What it produces is the project config,
# Pre/PostConfig and the AtlasCMake/AtlasLCG modules that Athena projects expect to find.
# Run inside the athena-dev container, after build-coral.sh.
set -euo pipefail
set +eu  # conda activation scripts are not written for "set -eu"
# shellcheck disable=SC1091
source /repo/athena-notes/spike/env.sh
set -eu

VERSION=25.0.73
PLATFORM=aarch64-cf-gcc15-opt
SRC=/work/src/atlasexternals
INSTALL=${PREFIX}/opt/athena/AthenaExternals/${VERSION}/InstallArea/${PLATFORM}
BLD=/work/build/externals

# atlasexternals 2.1.91 with our AtlasCMake/AtlasLCG patches.
rm -rf "${SRC}" && cp -r /repo/_work/atlasexternals "${SRC}"
python3 /repo/_work/atlascmake-conda-package/recipe/apply_patches.py "${SRC}/Build/AtlasCMake"
for p in /repo/athena-notes/spike/patches/atlasexternals/*.patch; do
  [ -e "$p" ] && patch -d "${SRC}" -p1 < "$p"
done

rm -rf "${BLD}" "${INSTALL}" && mkdir -p "${BLD}"
printf -- '- .*\n' > "${BLD}/package_filters.txt"
cd "${BLD}"
# shellcheck disable=SC2086
cmake -S "${SRC}/Projects/AthenaExternals" -B . -G Ninja ${CMAKE_ARGS} \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DCMAKE_INSTALL_PREFIX="${INSTALL}" \
  -DCMAKE_PROJECT_VERSION="${VERSION}" \
  -DLCG_VERSION_NUMBER=0 -DLCG_VERSION_POSTFIX="" \
  -DATLAS_PACKAGE_FILTER_FILE="${BLD}/package_filters.txt" \
  2>&1 | tee configure.log
ninja 2>&1 | tee build.log | tail -3
ninja install > install.log 2>&1
# The Find modules of the externals that AthenaExternals would build (yampl, ...): it only
# installs a package's module when it builds the package, and here they come from conda.
cp "${SRC}"/External/*/cmake/Find*.cmake "${INSTALL}/cmake/modules/"
# Our Find modules: replacements for AtlasLCG modules that do not work with conda-forge
# packages, and ATLAS's wrapper around Gaudi's configuration (it creates the plain
# "GaudiKernel" target that packages link against), which AthenaExternals only installs
# when it builds Gaudi itself.
cp /repo/athena-notes/spike/find-modules/*.cmake "${INSTALL}/cmake/modules/"
cat /repo/athena-notes/spike/conda-postconfig.cmake >> "${INSTALL}/cmake/PostConfig.cmake"
echo "AthenaExternals installed into ${INSTALL}"
