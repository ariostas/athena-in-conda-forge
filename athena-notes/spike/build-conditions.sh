#!/bin/bash
# Build the rest of the conditions client stack into the spike env: COOL 3_3_20 (on the
# CORAL from build-coral.sh), CrestApi 6.2.12 and chai 2.1.0, as atlasexternals 2.1.91
# configures them. Run inside the athena-dev container.
set -euo pipefail
set +eu  # conda activation scripts are not written for "set -eu"
# shellcheck disable=SC1091
source /repo/athena-notes/spike/env.sh
set -eu
mkdir -p /work/src /work/build && cd /work/src

build() {  # build <name> <source dir> <cmake args...>
  local name=$1 src=$2
  shift 2
  rm -rf "/work/build/${name}"
  # shellcheck disable=SC2086
  cmake -S "${src}" -B "/work/build/${name}" -G Ninja ${CMAKE_ARGS} \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_PREFIX_PATH="${PREFIX}" -DCMAKE_CXX_STANDARD=23 "$@" \
    > "/work/build/${name}-configure.log" 2>&1 \
    || { tail -40 "/work/build/${name}-configure.log"; return 1; }
  cmake --build "/work/build/${name}" --parallel "${JOBS:-8}" > "/work/build/${name}-build.log" 2>&1 \
    || { grep -E "error|FAILED" -A3 "/work/build/${name}-build.log" | head -40; return 1; }
  cmake --install "/work/build/${name}" > "/work/build/${name}-install.log" 2>&1
  echo "${name} installed"
}

rm -rf cool-COOL_3_3_20 && curl -sL https://gitlab.cern.ch/lcgcool/cool/-/archive/COOL_3_3_20/cool-COOL_3_3_20.tar.gz | tar xz
for p in /repo/athena-notes/spike/patches/cool/*.patch; do
  [ -e "$p" ] && patch -d cool-COOL_3_3_20 -p1 < "$p"
done
build cool cool-COOL_3_3_20 \
  -DBINARY_TAG=aarch64-cf-gcc15-opt -DLCG_python3=on \
  -DPYTHON_EXECUTABLE="${PREFIX}/bin/python" -DPython_config_version_twodigit=3.13 \
  -DBOOST_ROOT="${PREFIX}" -DCMAKE_POLICY_DEFAULT_CMP0167=OLD \
  -DCPPUNIT_INCLUDE_DIR="${PREFIX}/include" -DCPPUNIT_LIBRARY="${PREFIX}/lib/libcppunit.so" \
  -DXERCESC_INCLUDE_DIR="${PREFIX}/include" -DXERCESC_LIBRARY="${PREFIX}/lib/libxerces-c.so" \
  -DXERCESC_EXECUTABLE=DummyNotNeeded \
  -DTBB_INCLUDE_DIRS="${PREFIX}/include" -DTBB_LIBRARIES="${PREFIX}/lib/libtbb.so" \
  -DVDT_INCLUDE_DIRS="${PREFIX}/include" -DVDT_LIBRARIES="${PREFIX}/lib/libvdt.so"

rm -rf CrestApi-6.2.12 && curl -sL "https://gitlab.cern.ch/crest-db/CrestApi/-/archive/6.2.12/CrestApi-6.2.12.tar.gz" | tar xz
build crestapi CrestApi-6.2.12 \
  -DCMAKE_INSTALL_INCLUDEDIR=include/CrestApi -DCMAKE_INSTALL_LIBDIR=lib \
  -DCRESTAPI_BUILD_TOOLS=TRUE -DCRESTAPI_BUILD_EXAMPLES=FALSE -DBUILD_TESTING=FALSE

rm -rf chai-2.1.0 && curl -sL "https://gitlab.cern.ch/crest-db/chai/-/archive/2.1.0/chai-2.1.0.tar.gz" | tar xz
build chai chai-2.1.0 \
  -DCrestApi_DIR="${PREFIX}/lib/cmake/CrestApi" -DPython_EXECUTABLE="${PREFIX}/bin/python" \
  -DCMAKE_INSTALL_INCLUDEDIR=include/chai -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DBUILD_PYTHON_BINDINGS=ON -DCHAI_BUILD_TOOLS=TRUE
