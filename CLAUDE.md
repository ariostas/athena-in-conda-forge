# Athena in conda-forge

This repo is a fork of conda-forge/staged-recipes used only for packaging Athena (ATLAS
experiment software) for conda-forge. `PLAN.md` holds the plan, the decisions and the progress
log. Read it first, and add to its progress log (section 6) when something significant is
learned. The sister project is `../cmssw-in-conda-forge` (same approach for CMSSW); its
`CLAUDE.md` and `PLAN.md` record many lessons that apply here too.

## Layout

- `recipes/`: rattler-build (v1 `recipe.yaml`) recipes. `example-v1/` and `example-v0-deprecated/`
  are upstream staged-recipes examples; leave them alone.
- `athena-notes/`
  - `research/`: background reports (build system, externals vs conda-forge, package graph,
    prior art, runtime data and platforms).
  - `analysis/scripts/`: CMakeLists.txt parser, dependency graph, cost and layer partitioning
    (`layers.py`). python3 stdlib only; they read CVMFS and cache in `_work/`.
- `athena-notes/build-local.sh`: builds the recipes in the container (see below).
- `_work/` (git-ignored): clones (atlasexternals, the ATLAS Gaudi and CLHEP forks), repodata
  caches and analysis outputs.

## Reference material

- Reference release: Athena 25.0.73 (`release/25.0.73`, commit `8c1c4b757d2`).
- CVMFS is mounted on this machine (`atlas.cern.ch`, `atlas-condb.cern.ch`,
  `atlas-nightlies.cern.ch`, `sft.cern.ch`, plus the CMS ones). The installed release, with full
  `src/`, is at `/cvmfs/atlas.cern.ch/repo/sw/software/25.0/Athena/25.0.73/InstallArea/{aarch64,x86_64}-el9-gcc15-opt`,
  and its externals at `.../25.0/AthenaExternals/25.0.73/`. Reads are slow; keep scans targeted.
- Externals versions: atlasexternals 2.1.91, LCG_110_ATLAS_5, ROOT 6.40.02 (C++23), gcc 15.2.

## Building locally

The host is an arm64 Mac, so builds happen in Docker. `athena-dev` is `condaforge/miniforge3`
(native **linux-aarch64**) with the repo at `/repo`, `/cvmfs` read-only, and the volume
`athena-work` at `/work`: rattler-build and friends in `/work/tools/bin`, the conda-forge
pinning in `/work/conda_build_config.yaml`, an athena checkout of `release/25.0.73` in
`/work/athena`. The M1 spike environments (`/work/spike-env`, `/work/spike-build`) are
described in `athena-notes/spike/README.md`. Leave the `cmssw-dev*` containers alone.

Recipes are built with `athena-notes/build-local.sh` (adapted from the CMSSW one):
`docker exec athena-dev bash -c 'export PATH=/work/tools/bin:$PATH; cd /repo &&
./athena-notes/build-local.sh linux_aarch64 [recipes/<name> ...]'`. With no recipes it builds
all of them in dependency order. Packages go to `/work/output` (also used as a channel), logs
to `/work/logs/<name>-linux_aarch64.log`, and only python 3.13 is built.

- The image is Ubuntu-based: `/bin/sh` is dash, and CMake installs shared libraries without
  the execute bit unless `CMAKE_INSTALL_SO_NO_EXE=0`. conda-forge's CI is AlmaLinux.
- Scripts that `source` conda activation must do so with `set +eu` (bash errors out inside
  conda's `activate` function otherwise) and without redirecting the `source`.
- Do not edit a bash script while it is running.
- GitLab sometimes answers the athena archive URL with an empty 200 response. rattler-build then
  fails the sha256 check. The fix is to seed its cache: put the tarball in
  `/work/output/src_cache/<key>_<file>`, the unpacked tree (without the top directory) in
  `<key>_extracted`, and a `.metadata/<key>.json` like the other entries there.

## Conventions

- Run `prek -a --quiet` before committing. Revert its changes to pre-existing upstream files
  (e.g. `.github/`).
- Conventional commits with an `Assisted-by: <harness>:<model>` trailer.
- Recipe maintainer is `ariostas`. Follow staged-recipes requirements: license files, sha256,
  no symlinks in noarch packages, tests.
- Never ship ATLAS's `authentication.xml` (it holds Oracle passwords) or anything from CVMFS
  whose licence is unclear.
