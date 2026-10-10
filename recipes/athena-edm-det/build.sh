#!/bin/bash
set -euxo pipefail

# One layer of Athena, built as its own ATLAS project (Projects/CondaLayer, from this
# recipe's CMakeLists.txt) on top of the installed base project, and installed in the CVMFS
# layout: ${PREFIX}/opt/athena/<layer project>/<version>/InstallArea/<platform>.
LAYER=AthenaEDMDet
BASE=AthenaEDM

case "${target_platform}" in
  linux-64)      ARCH=x86_64 ;;
  linux-aarch64) ARCH=aarch64 ;;
  *) echo "Unsupported platform ${target_platform}"; exit 1 ;;
esac
PLATFORM=${ARCH}-cf-gcc$(${CXX} -dumpversion | cut -d. -f1)-opt
ROOT=${PREFIX}/opt/athena
INSTALL=${ROOT}/${LAYER}/${PKG_VERSION}/InstallArea/${PLATFORM}

# The compilers by absolute path: the base project's setup.sh puts the host prefix's bin/
# first in PATH, where root_base's own compiler (with the host's glibc 2.17 sysroot) lives.
CC=$(command -v "${CC}") CXX=$(command -v "${CXX}")
export CC CXX
# ATLAS does not build with conda-forge's -fvisibility-inlines-hidden, and its libraries rely on
# exporting inline functions: DATAVECTOR_BASE_FIN defines SG::bi_destroy<...>::destroy inline in
# the class's header, and code that sees only the forward declaration (DATAVECTOR_BASE_FWD) links
# to the copy in the class's library.
CXXFLAGS=${CXXFLAGS//-fvisibility-inlines-hidden/}
export CXXFLAGS

# The build loads and runs what it builds and what the layers below built (genconf,
# genCLIDDB, job options, python modules), and AtlasCMake sets no RPATH. ATLAS gets that
# environment from the base project's setup.sh, which sets up its own base projects in turn.
set +ux
# shellcheck disable=SC1090
source "${ROOT}/${BASE}/${PKG_VERSION}/InstallArea/${PLATFORM}/setup.sh"
set -ux
# ...without the host prefix's (glibc 2.17) sysroot, which root_base's compiler activation adds.
CMAKE_PREFIXES=$(tr ':' '\n' <<< "${CMAKE_PREFIX_PATH}" | grep -v -- "-conda-linux-gnu/sysroot" | paste -sd';')

sed -e '/^#/d' -e '/^$/d' -e 's/^/+ /' "${RECIPE_DIR}/packages.txt" > package_filters.txt
echo "- .*" >> package_filters.txt
# The layer project goes where ATLAS keeps its projects: some packages find the athena source
# tree as ${CMAKE_SOURCE_DIR}/../../.
mkdir -p Projects/CondaLayer
cp "${RECIPE_DIR}/CMakeLists.txt" Projects/CondaLayer/
# CMAKE_INSTALL_SO_NO_EXE: CMake's default on Debian-based hosts is to install shared libraries
# without the execute bit, and athena.py looks some of them up with "which". ATLAS_EXTERNAL:
# see the authentication.xml check below. ATLAS_ALWAYS_BUILD_TESTS: the packages' compiled
# unit tests are neither run nor installed here, and are about a third of the compile jobs.

cmake -S Projects/CondaLayer -B build -G Ninja ${CMAKE_ARGS} \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="${CMAKE_PREFIXES}" \
  -DCMAKE_INSTALL_PREFIX="${INSTALL}" \
  -DATLAS_FORCE_PLATFORM="${PLATFORM}" \
  -DATHENA_LAYER_NAME="${LAYER}" -DATHENA_LAYER_BASE="${BASE}" \
  -DATHENA_LAYER_VERSION="${PKG_VERSION}" \
  -DATHENA_SOURCE_DIR="${SRC_DIR}" \
  -DATLAS_PACKAGE_FILTER_FILE="${PWD}/package_filters.txt" \
  -DPython_EXECUTABLE="${PYTHON}" \
  -DCMAKE_INSTALL_SO_NO_EXE=0 \
  -DATLAS_EXTERNAL="${SRC_DIR}/no-atlas-external" \
  -DATLAS_ALWAYS_BUILD_TESTS=OFF
cmake --build build --parallel "${CPU_COUNT}"

# The unit tests of the packages in unit_tests.txt, which need no input files: built (each
# package has a Package_<name>_tests target) and run here, in the build area. ctest labels
# each test with its package's name. The packages' T/P converter tests (run_tpcnv_test) read
# files from CVMFS and the geometry database: the recipe's tests run them (tpcnv_tests.txt).
if [ -f "${RECIPE_DIR}/unit_tests.txt" ]; then
  tested=$(sed -e '/^#/d' -e '/^$/d' -e 's|.*/||' "${RECIPE_DIR}/unit_tests.txt")
  tpcnv=$(sed -E -e 's/^#(later|broken) //' -e '/^#/d' -e '/^$/d' "${RECIPE_DIR}/test/tpcnv_tests.txt" | awk '{print $2}')
  # shellcheck disable=SC2046
  cmake --build build --parallel "${CPU_COUNT}" --target $(sed 's/.*/Package_&_tests/' <<< "${tested}")
  ctest --test-dir build --output-on-failure --parallel "${CPU_COUNT}" \
    --label-regex "^($(paste -sd'|' <<< "${tested}"))$" \
    --exclude-regex "_($(paste -sd'|' <<< "${tpcnv}"))_ctest$"
fi

cmake --install build

# ATLAS's authentication.xml holds database passwords: AtlasAuthentication installs it when it
# finds it in ${ATLAS_EXTERNAL} (on AFS by default), which is pointed nowhere above. The
# install area also carries the packages' sources (src/), as on CVMFS, and one package keeps
# an authentication.xml with credentials in its sources (PixelConditionsTools/share/): no
# copy of it is shipped.
find "${INSTALL}/src" -name authentication.xml -print -delete
if find "${INSTALL}" -name authentication.xml | grep .; then
  echo "authentication.xml must not be packaged"
  exit 1
fi

# Activation: the layer's own setup.sh, as on CVMFS (see activate.sh).
mkdir -p "${PREFIX}/etc/conda/activate.d" "${PREFIX}/etc/conda/deactivate.d"
sed -e "s|@LAYER@|${LAYER}|g" -e "s|@PLATFORM@|${PLATFORM}|g" -e "s|@VERSION@|${PKG_VERSION}|g" \
  "${RECIPE_DIR}/activate.sh" > "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"
sed -e "s|@LAYER@|${LAYER}|g" \
  "${RECIPE_DIR}/deactivate.sh" > "${PREFIX}/etc/conda/deactivate.d/${PKG_NAME}_deactivate.sh"
