#!/bin/bash
# Build one Athena layer as an ATLAS project on top of the already installed ones.
#
# usage: build-layer.sh <layer name> <base project> <package> [<package> ...]
# Run inside the athena-dev container, after build-externals.sh. Every project is installed
# in the CVMFS shape: ${PREFIX}/opt/athena/<Project>/<version>/InstallArea/<platform>.
set -euo pipefail
NAME=$1 BASE=$2
shift 2
set +eu  # conda activation scripts are not written for "set -eu"
# shellcheck disable=SC1091
source /repo/athena-notes/spike/env.sh
set -eu

VERSION=25.0.73
PLATFORM=aarch64-cf-gcc15-opt
ROOT=${PREFIX}/opt/athena
SRC=/work/athena
BLD=/work/build/${NAME}
INSTALL=${ROOT}/${NAME}/${VERSION}/InstallArea/${PLATFORM}

# The build loads and runs what the layers below built (genconf, genCLIDDB, job options), and
# AtlasCMake sets no RPATH. ATLAS gets that environment from the base release's setup.sh,
# which sets up its own base projects in turn when installed in the CVMFS shape, as here.
# In conda this will be the layers' activation scripts.
# (setup.sh is not written for "set -u".)
set +u
# shellcheck disable=SC1090
source "${ROOT}/${BASE}/${VERSION}/InstallArea/${PLATFORM}/setup.sh"
set -u
CMAKE_PREFIXES=$(strip_host_sysroot "${CMAKE_PREFIX_PATH}")
CMAKE_PREFIXES="${CMAKE_PREFIXES//:/;}"

rm -rf "${BLD}" "${INSTALL}" && mkdir -p "${BLD}"
for p in "$@"; do echo "+ $p"; done > "${BLD}/package_filters.txt"
echo "- .*" >> "${BLD}/package_filters.txt"
# The layer project goes where ATLAS keeps its projects: some packages find the athena
# source tree as ${CMAKE_SOURCE_DIR}/../../.
rm -rf "${SRC}/Projects/CondaLayer" && cp -r /repo/athena-notes/spike/layer "${SRC}/Projects/CondaLayer"
cd "${BLD}"
start=$(date +%s)
# shellcheck disable=SC2086
cmake -S "${SRC}/Projects/CondaLayer" -B . -G Ninja ${CMAKE_ARGS} \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="${CMAKE_PREFIXES}" \
  -DCMAKE_INSTALL_PREFIX="${INSTALL}" \
  -DATHENA_LAYER_NAME="${NAME}" -DATHENA_LAYER_BASE="${BASE}" \
  -DATHENA_SOURCE_DIR="${SRC}" \
  -DATLAS_PACKAGE_FILTER_FILE="${BLD}/package_filters.txt" \
  -DCMAKE_INSTALL_SO_NO_EXE=0 \
  -DPython_EXECUTABLE="${PREFIX}/bin/python" \
  > configure.log 2>&1 || { tail -40 configure.log; exit 1; }
configured=$(date +%s)
ninja -j"${JOBS:-8}" > build.log 2>&1 || { grep -E "error|FAILED" -A3 build.log | head -60; exit 1; }
built=$(date +%s)
ninja install > install.log 2>&1 || { tail -20 install.log; exit 1; }
echo "${NAME}: configure $((configured - start)) s, build $((built - configured)) s; installed into ${INSTALL}"
