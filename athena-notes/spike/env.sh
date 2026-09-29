# Environment for the spike scripts, set up the way rattler-build does: a host prefix with
# the libraries (ROOT, Gaudi, ...) and a separate build prefix with the compilers and a
# glibc 2.34 sysroot (EL9's glibc, what ATLAS builds for; root_base pins its own prefix to
# 2.17, which lacks mallinfo2 and has the old _dlfcn_hook). Sourced by the other scripts.
# shellcheck disable=SC1091
source /opt/conda/etc/profile.d/conda.sh
conda activate /work/spike-env
export PREFIX=/work/spike-env BUILD_PREFIX=/work/spike-build CONDA_BUILD=1
export SRC_DIR=/work/src PKG_NAME=athena-spike PKG_VERSION=0
conda activate --stack /work/spike-build
export PATH=${PATH}:/work/tools/bin
export LANG=C.UTF-8 LC_ALL=C.UTF-8
unset PIP_ROOT
# The compilers by absolute path: conda sets them as bare names, and the setup.sh of an
# installed Athena layer (sourced by build-layer.sh) puts the host prefix's bin/ first in
# PATH, where root_base's own compiler (with the host's glibc 2.17 sysroot) lives.
CC=$(command -v "${CC}") CXX=$(command -v "${CXX}") FC=$(command -v "${FC}")
export CC CXX FC
