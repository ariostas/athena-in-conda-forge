#!/bin/bash
# Build the Athena recipes locally, inside a conda-forge style container.
#
# usage: [WORK=<dir>] [KEEP_BUILD=1] build-local.sh <ci-config> [recipe ...]
#   e.g. build-local.sh linux_aarch64   (in the athena-dev container, repo mounted at /repo)
# ci-config is one of the files in .ci_support (without .yaml). WORK (default /work) must contain
# conda_build_config.yaml (the conda-forge global pinning). Packages are written to $WORK/output,
# which is also used as a channel, so recipes must be given in dependency order. KEEP_BUILD=1
# keeps the build directories (in $WORK/output/bld), e.g. to look at the ninja log.
# Adapted from ../cmssw-in-conda-forge/cmssw-notes/build-local.sh.
set -euo pipefail

CONFIG=$1
shift
RECIPES=("$@")
if [ ${#RECIPES[@]} -eq 0 ]; then
  RECIPES=(recipes/boost-mpi3 recipes/yampl recipes/tdaq-common recipes/frontier-client recipes/lcg-coral recipes/lcg-cool
           recipes/crestapi recipes/chai recipes/atlas-gaudi recipes/athena-externals)
fi

WORK=$(mkdir -p "${WORK:-/work}" && cd "${WORK:-/work}" && pwd)
# Two runs would share the output directory and the per-recipe logs.
exec 9>"${WORK}/.build-local.lock"
if command -v flock >/dev/null && ! flock -n 9; then
  echo "another build-local.sh is running in ${WORK}; wait for it or kill it" >&2
  exit 1
fi
cd "$(dirname "$0")/.."
OUT=${WORK}/output
mkdir -p "${OUT}" "${WORK}/logs"
# use the local output directory as an additional channel
sed -E "s|^( *)- conda-forge$|\1- ${OUT},conda-forge|" ".ci_support/${CONFIG}.yaml" > "${WORK}/${CONFIG}_local.yaml"
# only one python version for local testing: the one ATLAS uses
printf 'python:\n  - 3.13.* *_cp313\nis_python_min:\n  - false\n' > "${WORK}/local_variants.yaml"

# Rebuilding a recipe without bumping its build number reuses the already extracted package
# from rattler's cache, so drop the cached copies of what we are about to rebuild.
PKG_CACHE=${RATTLER_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/rattler/cache}/pkgs

for recipe in "${RECIPES[@]}"; do
  name=$(basename "${recipe}")
  rm -rf "${PKG_CACHE}/${name}-"*
  # rattler-build only indexes files it does not know yet, so a package rebuilt under the same
  # file name would keep its first build's entry. Let it index the directory again.
  rm -f "${OUT}"/*/repodata.json "${OUT}"/*/repodata_from_packages.json
  echo ">> building ${recipe} (log: ${WORK}/logs/${name}-${CONFIG}.log)"
  start=$(date +%s)
  # explicit -m disables the auto-discovery of the recipe's variants.yaml, add it last so it wins
  recipe_variants=()
  [ -f "${recipe}/variants.yaml" ] && recipe_variants+=(-m "${recipe}/variants.yaml")
  keep=()
  [ "${KEEP_BUILD:-0}" = 1 ] && keep+=(--keep-build)
  if rattler-build build --recipe "${recipe}" --output-dir "${OUT}" ${keep[@]+"${keep[@]}"} \
      -m "${WORK}/${CONFIG}_local.yaml" -m "${WORK}/conda_build_config.yaml" \
      -m "${WORK}/local_variants.yaml" ${recipe_variants[@]+"${recipe_variants[@]}"} \
      > "${WORK}/logs/${name}-${CONFIG}.log" 2>&1; then
    echo "   ok ($(( $(date +%s) - start )) s)"
  else
    echo "   FAILED ($(( $(date +%s) - start )) s)"
    tail -20 "${WORK}/logs/${name}-${CONFIG}.log"
    exit 1
  fi
done
