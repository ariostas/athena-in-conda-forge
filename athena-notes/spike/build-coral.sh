#!/bin/bash
# Build upstream CORAL 3_3_20 (what AthenaExternals uses) into the spike env, without
# Oracle (not redistributable), the CORAL server (needs Sun RPC) or Frontier (for now).
# Run inside the athena-dev container.
set -euo pipefail
set +eu  # conda activation scripts are not written for "set -eu"
# shellcheck disable=SC1091
source /repo/athena-notes/spike/env.sh
set -eu
SRC=/work/src/coral-CORAL_3_3_20
# Fresh source with our patches applied.
rm -rf "${SRC}" && mkdir -p /work/src && cd /work/src
curl -sL https://gitlab.cern.ch/lcgcoral/coral/-/archive/CORAL_3_3_20/coral-CORAL_3_3_20.tar.gz | tar xz
for p in /repo/athena-notes/spike/patches/coral/*.patch; do patch -d "${SRC}" -p1 < "$p"; done
BLD=/work/build/coral
rm -rf "${BLD}" && mkdir -p "${BLD}"
cd "${BLD}"
# CMAKE_ARGS from the compiler activation carries the conda toolchain settings.
# shellcheck disable=SC2086
cmake -S "${SRC}" -B . -G Ninja ${CMAKE_ARGS} \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DBINARY_TAG=aarch64-cf-gcc15-opt \
  -DCMAKE_CXX_STANDARD=23 \
  -DLCG_python3=on \
  -DPYTHON_EXECUTABLE="${PREFIX}/bin/python" \
  -DPython_config_version_twodigit=3.13 \
  -DBOOST_ROOT="${PREFIX}" \
  -DXERCESC_INCLUDE_DIR="${PREFIX}/include" \
  -DXERCESC_LIBRARY="${PREFIX}/lib/libxerces-c.so" \
  -DXERCESC_EXECUTABLE=DummyNotNeeded \
  -DSQLITE_INCLUDE_DIR="${PREFIX}/include" \
  -DSQLITE_LIBRARY="${PREFIX}/lib/libsqlite3.so" \
  -DSQLITE_EXECUTABLE=DummyNotNeeded \
  -DEXPAT_EXECUTABLE=DummyNotNeeded \
  -DCPPUNIT_INCLUDE_DIR="${PREFIX}/include" \
  -DCPPUNIT_LIBRARY="${PREFIX}/lib/libcppunit.so" \
  -DCORAL_BUILD_MYSQL=OFF -DCORAL_BUILD_ORACLE=OFF -DCORAL_BUILD_FRONTIER=OFF \
  -DCORAL_BUILD_TESTS=OFF -DCORAL_BUILD_SERVER=OFF \
  -DCMAKE_POLICY_DEFAULT_CMP0167=OLD \
  -DCMAKE_DISABLE_FIND_PACKAGE_IgProf=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_gperftools=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_Valgrind=ON \
  2>&1 | tee configure.log
ninja -j"${JOBS:-8}" 2>&1 | tee build.log | tail -5
ninja install > install.log 2>&1
echo "CORAL installed into ${PREFIX}"
