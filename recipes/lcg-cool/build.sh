#!/bin/bash
set -euxo pipefail

# COOL wants a platform tag a priori, like CORAL (see lcg-coral).
case "${target_platform}" in
  linux-64)      BINARY_TAG=x86_64-conda-gcc-opt ;;
  linux-aarch64) BINARY_TAG=aarch64-conda-gcc-opt ;;
  osx-arm64)     BINARY_TAG=arm64-conda-clang-opt ;;
  *) echo "Unsupported platform ${target_platform}"; exit 1 ;;
esac

# COOL's Find modules require the command-line tools of its dependencies, which it does not
# use, and CORAL's python module in the LCG layout (lcg-coral has it in site-packages). PyCool
# is built on ROOT's cppyy; the build only compiles its headers against ROOT's.
cmake -S . -B build -G Ninja ${CMAKE_ARGS} \
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
  -DCORAL_PYTHON_PATH="${SP_DIR}" \
  -DCMAKE_DISABLE_FIND_PACKAGE_IgProf=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_gperftools=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_Valgrind=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_QMTest=ON
cmake --build build --parallel "${CPU_COUNT}"
cmake --install build

# COOL installs in the LCG layout: python packages in <prefix>/python, plus examples, tests
# and Oracle administration scripts. Keep the libraries, the command-line tools and PyCool.
mkdir -p "${SP_DIR}"
mv "${PREFIX}"/python/* "${SP_DIR}/"
rmdir "${PREFIX}/python"
rm -rf "${PREFIX}/examples" "${PREFIX}/CoolTest" "${PREFIX}/tests" "${PREFIX}/bin/sql"
rm -f "${PREFIX}/bin/coolExecuteSql.csh" "${PREFIX}/bin/coolSqlplus.sh"
rm -f "${PREFIX}"/{cc-run,cc-sh,env.sh,env.csh,setup.sh,setup.csh}
