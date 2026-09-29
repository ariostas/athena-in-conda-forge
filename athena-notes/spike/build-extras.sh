#!/bin/bash
# Build the small externals that AthenaExternals builds itself and conda-forge lacks
# (boost-mpi3 with ATLAS's patch, yampl) into the spike env. Run inside the container.
set -euo pipefail
set +eu  # conda activation scripts are not written for "set -eu"
# shellcheck disable=SC1091
source /repo/athena-notes/spike/env.sh
set -eu
AE=/repo/_work/atlasexternals
mkdir -p /work/src /work/build && cd /work/src

# boost-mpi3 v0.81: header-only, plus a CMake configuration (bmpi3Config.cmake).
rm -rf boost-mpi3-v0.81 && curl -sL http://cern.ch/atlas-software-dist-eos/externals/boost-mpi3/boost-mpi3-v0.81.tar.gz | tar xz
patch -d boost-mpi3-v0.81 -p1 < "${AE}/External/boost-mpi3/patches/boost-mpi3-v0.81.patch"
# shellcheck disable=SC2086
cmake -S boost-mpi3-v0.81 -B /work/build/boost-mpi3 -G Ninja ${CMAKE_ARGS} \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DCMAKE_BUILD_TYPE=Release > /work/build/boost-mpi3.log 2>&1
cmake --build /work/build/boost-mpi3 >> /work/build/boost-mpi3.log 2>&1
cmake --install /work/build/boost-mpi3 >> /work/build/boost-mpi3.log 2>&1
echo "boost-mpi3 installed"

# yampl 1.2 (autotools).
rm -rf yampl && curl -sL http://cern.ch/atlas-software-dist-eos/externals/yampl/yampl-v1.2.tar.bz2 | tar xj
patch -d yampl -p1 < /repo/athena-notes/spike/patches/yampl/0001-use-system-zeromq.patch
rm -rf yampl/zeromq
cd yampl
CXXFLAGS="${CXXFLAGS} -I${PREFIX}/include" ./configure --prefix="${PREFIX}" \
  > /work/build/yampl.log 2>&1
make -j8 >> /work/build/yampl.log 2>&1
make install >> /work/build/yampl.log 2>&1
echo "yampl installed"
