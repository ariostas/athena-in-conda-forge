#!/bin/bash

set -ex

# c.f. https://conda-forge.org/docs/maintainer/knowledge_base/#cross-compilation-examples
# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* .

autoreconf --install --force

./configure --help

./configure \
    --prefix=$PREFIX \
    --enable-shared=yes \
    --enable-static=no \
    --disable-doxygen \
    --with-yoda=$PREFIX \
    --with-hepmc3=$PREFIX \
    --with-fastjet=$PREFIX \
    --with-fjcontrib=$PREFIX \
    --with-zlib=$PREFIX \
    PYTHON=$PYTHON

make --jobs="${CPU_COUNT}"

# Skip ``make check`` when cross-compiling
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR:-}" != "" ]]; then
  make check || { cat test/test-suite.log; exit 1; }
fi
make install
make clean

# The configure-time value of CXXFLAGS, which contains
# -fdebug-prefix-map=<build work dir>=... flags, gets baked into the
# installed helper scripts, leaking build machine paths that conda prefix
# relocation does not rewrite. Strip the flags, and guard against any build
# machine path surviving. The recorded compiler is intentionally left as the
# activation's bare name (e.g. x86_64-conda-linux-gnu-c++), which the
# minimally activated compilers resolve from PATH in end user environments.
for script in "${PREFIX}/bin/rivet-build" "${PREFIX}/bin/rivet-config"; do
    sed -i -E 's@(^|[[:space:]"])-f[a-z-]+-prefix-map=[^ "]*@\1@g' "${script}"
    if grep -E 'prefix-map=' "${script}" \
        || grep -F -e "${BUILD_PREFIX}" -e "${SRC_DIR}" "${script}"; then
        echo "ERROR: build machine paths leaked into ${script}" >&2
        exit 1
    fi
done

# Shell completions
# Bash completions
mkdir -p "${PREFIX}"/share/bash-completion/completions
cp ./bin/rivet-completion "${PREFIX}"/share/bash-completion/completions/rivet

# ZSH completions
mkdir -p "${PREFIX}"/share/zsh/site-functions
cp ./bin/rivet-completion "${PREFIX}"/share/zsh/site-functions/_rivet
