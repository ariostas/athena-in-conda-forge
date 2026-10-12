#!/bin/bash
set -euxo pipefail

# On macOS conda-forge's libc++ headers mark library features newer than the deployment target
# as unavailable (libc++ 20's markup of std::from_chars does not even compile); the environments
# have conda-forge's own, current libc++ at run time.
if [[ "${target_platform}" == osx-* ]]; then
  export CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
fi

# CORAL wants a platform tag a priori; it only uses it to name things and to pick compiler
# flags (by matching "gcc"/"clang" in it).
case "${target_platform}" in
  linux-64)      BINARY_TAG=x86_64-conda-gcc-opt ;;
  linux-aarch64) BINARY_TAG=aarch64-conda-gcc-opt ;;
  osx-arm64)     BINARY_TAG=arm64-conda-clang-opt ;;
  *) echo "Unsupported platform ${target_platform}"; exit 1 ;;
esac

# The packages' tests are compiled even when they are not run, and use std::auto_ptr, which
# libc++ (macOS) only has on request in C++17 and later.
if [[ "${target_platform}" == osx-* ]]; then
  export CXXFLAGS="${CXXFLAGS} -D_LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR"
fi

# Without Oracle (not redistributable), MySQL (not used by ATLAS or CMS), the CORAL server
# (needs Sun RPC) and the tests (they need database accounts). CORAL's Find modules also
# require the command-line tools of its dependencies, which it does not use.
cmake -S . -B build -G Ninja ${CMAKE_ARGS} -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DCMAKE_CXX_STANDARD=23 \
  -DBINARY_TAG="${BINARY_TAG}" \
  -DLCG_python3=on \
  -DPYTHON_EXECUTABLE="${PYTHON}" \
  -DPython_config_version_twodigit="${PY_VER}" \
  -DBOOST_ROOT="${PREFIX}" \
  -DCMAKE_POLICY_DEFAULT_CMP0167=OLD \
  -DXERCESC_EXECUTABLE=NotNeeded \
  -DSQLITE_EXECUTABLE=NotNeeded \
  -DEXPAT_EXECUTABLE=NotNeeded \
  -DFRONTIER_CLIENT_EXECUTABLE=NotNeeded \
  -DCORAL_BUILD_MYSQL=OFF -DCORAL_BUILD_ORACLE=OFF -DCORAL_BUILD_FRONTIER=ON \
  -DCORAL_BUILD_TESTS=OFF -DCORAL_BUILD_SERVER=OFF \
  -DCMAKE_DISABLE_FIND_PACKAGE_IgProf=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_gperftools=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_Valgrind=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_QMTest=ON
cmake --build build --parallel "${CPU_COUNT}"
cmake --install build

# CORAL installs in the LCG layout: python modules in <prefix>/python, and the test and
# profiling helpers next to the libraries. PyCoral is the library itself ("coral.py" imports
# liblcg_PyCoral), so both go into site-packages.
mkdir -p "${SP_DIR}"
mv "${PREFIX}/python/coral.py" "${SP_DIR}/"
# (On macOS CORAL names its libraries .so, with a .dylib link: python wants the .so.)
mv "${PREFIX}/lib/liblcg_PyCoral.so" "${SP_DIR}/"
rm -f "${PREFIX}/lib/liblcg_PyCoral.dylib"
rmdir "${PREFIX}/python"
rm -rf "${PREFIX}/CoralTest"
rm -f "${PREFIX}"/bin/coral*Wrapper.sh "${PREFIX}"/bin/igprof-navigator-index.php \
  "${PREFIX}"/bin/valgrind*.supp
# CORAL's own environment scripts for its build area
rm -f "${PREFIX}"/{cc-run,cc-sh,env.sh,env.csh,setup.sh,setup.csh}
# On macOS the build copies /usr/bin/env into bin/ (for its own environment scripts, around
# System Integrity Protection). Current macOS kills copies of system binaries, and this one
# would shadow the system's env in the environment.
rm -f "${PREFIX}/bin/env"
