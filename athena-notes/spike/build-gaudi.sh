#!/bin/bash
# Build ATLAS's Gaudi fork (v40r4.002, what AthenaExternals 25.0.73 uses) into the spike env
# with the same compiler as Athena. conda-forge's gaudi 40.4 is built with gcc 14 and exports
# libstdc++'s std::format internals, which Athena code built with gcc 15 then binds to and
# crashes in (genconf on any component with a double property). Run inside the container.
set -euo pipefail
set +eu  # conda activation scripts are not written for "set -eu"
# shellcheck disable=SC1091
source /repo/athena-notes/spike/env.sh
set -eu
SRC=/work/src/Gaudi-v40r4.002
BLD=/work/build/gaudi
cd /work/src
rm -rf "${SRC}" && curl -sL https://gitlab.cern.ch/atlas/Gaudi/-/archive/v40r4.002/Gaudi-v40r4.002.tar.gz | tar xz
rm -rf "${BLD}"
# Options from conda-forge's gaudi recipe.
# shellcheck disable=SC2086
cmake -S "${SRC}" -B "${BLD}" -G Ninja ${CMAKE_ARGS} \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
  -DCMAKE_CXX_STANDARD=23 \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_TESTING=OFF \
  -DGAUDI_INSTALL_PYTHONDIR="$("${PREFIX}/bin/python" -c 'import sysconfig; print(sysconfig.get_path("purelib"))')" \
  -DGAUDI_DEFAULT_PLUGIN_PATH="${PREFIX}/lib" \
  -DPython_EXECUTABLE="${PREFIX}/bin/python" \
  -DGAUDI_USE_DOXYGEN=OFF \
  > /work/build/gaudi-configure.log 2>&1 || { tail -40 /work/build/gaudi-configure.log; exit 1; }
cmake --build "${BLD}" --parallel "${JOBS:-8}" > /work/build/gaudi-build.log 2>&1 \
  || { grep -E "error|FAILED" -A3 /work/build/gaudi-build.log | head -40; exit 1; }
cmake --install "${BLD}" > /work/build/gaudi-install.log 2>&1
echo "Gaudi installed into ${PREFIX}"
