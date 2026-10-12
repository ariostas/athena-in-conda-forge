#!/bin/bash
set -euxo pipefail

# One layer of Athena, built as its own ATLAS project (Projects/CondaLayer, from this
# recipe's CMakeLists.txt) on top of the installed base project, and installed in the CVMFS
# layout: ${PREFIX}/opt/athena/<layer project>/<version>/InstallArea/<platform>.
LAYER=AthenaCore
BASE=AthenaExternals

case "${target_platform}" in
  linux-64)      ARCH=x86_64  COMPILER=gcc ;;
  linux-aarch64) ARCH=aarch64 COMPILER=gcc ;;
  osx-arm64)     ARCH=arm64   COMPILER=clang ;;
  *) echo "Unsupported platform ${target_platform}"; exit 1 ;;
esac
PLATFORM=${ARCH}-cf-${COMPILER}$(${CXX} -dumpversion | cut -d. -f1)-opt
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
# __FILE__ of the headers installed in the host prefix (the layers below, the externals) puts the
# prefix into the libraries' read-only strings, and packaging rewrites it in place: the shorter
# installed prefix, padded with NULs. The linker stores a string literal that is the tail of
# another one inside it, and such a literal then becomes empty: a property name of
# BJetThreeValueCheck, "c", lived at the end of ".../AthCommonDataStore.icc" and was lost. So the
# prefix is mapped in __FILE__, as conda-forge's flags already do for the debug information.
CFLAGS="${CFLAGS} -fmacro-prefix-map=${PREFIX}=/usr/local/src/conda-prefix"
CXXFLAGS="${CXXFLAGS} -fmacro-prefix-map=${PREFIX}=/usr/local/src/conda-prefix"
export CFLAGS CXXFLAGS

# The build loads and runs what it builds and what the layers below built (genconf,
# genCLIDDB, job options, python modules), and AtlasCMake sets no RPATH. ATLAS gets that
# environment from the base project's setup.sh, which sets up its own base projects in turn.
set +ux
# shellcheck disable=SC1090
source "${ROOT}/${BASE}/${PKG_VERSION}/InstallArea/${PLATFORM}/setup.sh"
set -ux
# ...without the host prefix's (glibc 2.17) sysroot, which root_base's compiler activation adds.
CMAKE_PREFIXES=$(tr ':' '\n' <<< "${CMAKE_PREFIX_PATH}" | grep -v -- "-conda-linux-gnu/sysroot" | paste -sd';' -)

# On macOS the libraries find each other through rpaths (athena-externals' AtlasCMake patch
# 0005): this layer's lib/, the layers' below it and the prefix's.
RPATH_ARGS=()
if [[ "${target_platform}" == osx-* ]]; then
  rpath="${INSTALL}/lib"
  for dir in "${ROOT}"/*/"${PKG_VERSION}"/InstallArea/"${PLATFORM}"/lib; do
    rpath="${rpath};${dir}"
  done
  RPATH_ARGS=(-DCMAKE_INSTALL_RPATH="${rpath};${PREFIX}/lib")
fi

# The packages that cannot be built on macOS (packages_excluded_osx.txt, with the reasons) come
# first, as exclusions: the first matching line decides.
: > package_filters.txt
if [[ "${target_platform}" == osx-* ]] && [ -f "${RECIPE_DIR}/packages_excluded_osx.txt" ]; then
  sed -e 's/#.*//' -e '/^ *$/d' -e 's/ *$//' -e 's/^/- /' \
    "${RECIPE_DIR}/packages_excluded_osx.txt" > package_filters.txt
fi
sed -e '/^#/d' -e '/^$/d' -e 's/^/+ /' "${RECIPE_DIR}/packages.txt" >> package_filters.txt
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
  -DATLAS_ALWAYS_BUILD_TESTS=OFF \
  ${RPATH_ARGS[@]+"${RPATH_ARGS[@]}"}
cmake --build build --parallel "${CPU_COUNT}"
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

# The exported targets must not name files of the build environment, which does not exist when
# the next layer is built (glibc's libraries in the compiler's sysroot: see athena-externals'
# conda-postconfig.cmake).
if grep -l "${BUILD_PREFIX}" "${INSTALL}"/cmake/*.cmake; then
  echo "the layer's CMake configuration names files of the build environment"
  exit 1
fi

# Activation: the layer's own setup.sh, as on CVMFS (see activate.sh).
mkdir -p "${PREFIX}/etc/conda/activate.d" "${PREFIX}/etc/conda/deactivate.d"
sed -e "s|@LAYER@|${LAYER}|g" -e "s|@PLATFORM@|${PLATFORM}|g" -e "s|@VERSION@|${PKG_VERSION}|g" \
  "${RECIPE_DIR}/activate.sh" > "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"
sed -e "s|@LAYER@|${LAYER}|g" \
  "${RECIPE_DIR}/deactivate.sh" > "${PREFIX}/etc/conda/deactivate.d/${PKG_NAME}_deactivate.sh"
# Downloads of GroupData files (see groupdata-activate.sh).
cp "${RECIPE_DIR}/groupdata-activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_groupdata.sh"
cp "${RECIPE_DIR}/groupdata-deactivate.sh" "${PREFIX}/etc/conda/deactivate.d/${PKG_NAME}_groupdata.sh"
