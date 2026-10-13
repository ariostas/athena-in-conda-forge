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

`athena-ref` (`almalinux:9`, `/cvmfs` and `/work` mounted) runs ATLAS's own release from CVMFS,
as the reference for what a job should do and which packages it needs:
`docker exec -w <dir> athena-ref bash /work/tmp/cvmfs-athena.sh <command>`, a copy of
`athena-notes/cvmfs-athena.sh`. That script sources the LCG gcc and the release's `setup.sh`, and
sets `ATLAS_POOLCOND_PATH` and `FRONTIER_SERVER` (ATLAS's public Frontier server, directly: the
proxy that `asetup` adds answers 403 from here). First reads from CVMFS are slow (minutes).
`athena-notes/analysis/scripts/cfgdeps.py`, run the same way, lists the python packages and
component types a configuration (a module or a job script) uses; `cfgmap.py` maps that to
packages and layers. The container has the EL9 packages the release needs beyond the base
image (libicu, libcurl, libuuid-devel for cling, libbrotli for ROOT's TreePlayer, diffutils
for ATLAS's tests, procps-ng for the job transforms, which for athena.py, glibc-devel for
linking with LCG's gcc); install missing ones one at a time
(`dnf install` gives up on the batch; libcurl needs `--allowerasing`).
If the host's CVMFS is remounted, the containers see it again without a restart. Everything
that matters lives in the `athena-work` volume, so the containers can be recreated (README's
`docker run` lines; athena-ref is `almalinux:9` with the same `/work` and `/cvmfs` mounts):
`docker system prune` removes them when they are stopped.

Recipes are built with `athena-notes/build-local.sh` (adapted from the CMSSW one):
`docker exec athena-dev bash -c 'export PATH=/work/tools/bin:$PATH; cd /repo &&
./athena-notes/build-local.sh linux_aarch64 [recipes/<name> ...]'`. With no recipes it builds
all of them except the Athena layers, in dependency order. Packages go to `/work/output` (also
used as a channel), logs to `/work/logs/<name>-linux_aarch64.log`, and only python 3.13 is
built. `KEEP_BUILD=1` keeps the build directories in `/work/output/bld`, for
`athena-notes/analysis/scripts/compile_cost.py` (compile time and memory of a layer; it runs
ninja, so put the build's `build_env/bin` first in `PATH`).

- Builds use at most 5 threads, so that the laptop stays usable: `build-local.sh` sets
  `CPU_COUNT=5` unless given, and the containers are capped with `docker update --cpus 5`
  (recreated containers need it again). Use `ninja -j5` for manual runs.
- The image is Ubuntu-based: `/bin/sh` is dash, and CMake installs shared libraries without
  the execute bit unless `CMAKE_INSTALL_SO_NO_EXE=0`. conda-forge's CI is AlmaLinux.
- Scripts that `source` conda activation must do so with `set +eu` (bash errors out inside
  conda's `activate` function otherwise) and without redirecting the `source`.
- Do not edit a bash script while it is running.
- Run long jobs detached inside the containers (`docker exec -d`), not as a background
  `docker exec` from the host: when the host-side client is killed, the job dies with it.
  `athena-notes/bg-build.sh <recipe> ...` (copied to `/work/bg-build.sh` in athena-dev) runs
  `build-local.sh` that way, exit code in `/work/logs/bg-build.rc`;
  `athena-notes/bg.sh <dir> <name> <command>` (`/work/tmp/bg.sh`, for athena-ref) runs a
  command in `<dir>`, output in `<name>.out`, exit code in `<name>.rc`.
- When a recipe's test fails after a long build, fix and check it in the test environment
  rattler-build leaves behind (`/work/output/test/test_<name>*/test_run_env`): install what is
  missing there (`conda install -p ...`) and rerun its `test/conda_build.sh`, before rebuilding.
  `conda run -p <env>` runs a command with the environment activated (the layers' setup.sh).
- A failure only in the packaged binaries, not in the build tree's, points at packaging's
  binary prefix replacement: compare the two, and relocate a build-tree library as packaging
  does (`athena-notes/analysis/scripts/relocate.py`). The layers map the prefix out of
  `__FILE__` for this reason (PLAN.md, M6).
- GitLab sometimes answers the athena archive URL with an empty 200 response. rattler-build then
  fails the sha256 check. The fix is to seed its cache: put the tarball in
  `/work/output/src_cache/<key>_<file>`, the unpacked tree (without the top directory) in
  `<key>_extracted`, and a `.metadata/<key>.json` like the other entries there.
- Every ATLAS project installs a copy of its base project's CMake find modules and of
  AtlasCMake's modules, and the copy of the layer just below comes first. A change to
  athena-externals' `cmake/Find*.cmake`, or a patch to AtlasCMake, reaches a layer only once
  every layer below it is rebuilt (its `conda-postconfig.cmake` is read from
  AthenaExternals itself, so it reaches every layer right away).
- To try configure or compile fixes without a full recipe build, use a kept build tree
  (`KEEP_BUILD=1`): its `work/conda_build.sh` is `build.sh` inside `( ... )` after the
  environment setup; a truncated copy (closing the parenthesis) reruns any part of it. For
  tests without CVMFS or network, as on conda-forge's CI, run them in a throwaway container:
  `docker run --rm --network none -v athena-work:/work condaforge/miniforge3:latest ...`.

### linux-64 (M8)

- `athena-dev-amd64`: `quay.io/condaforge/linux-anvil-x86_64:alma9` (conda-forge's CI image),
  `--platform linux/amd64` (Rosetta, about 2.6x slower), run as `-u root`, the repo at `/repo`,
  `/cvmfs`, and its own volume `athena-work-amd64` at `/work` (tools, pinning, output, logs as
  in athena-dev). `CONFIG=linux64 /work/bg-build.sh <recipe> ...` builds detached;
  `/work/chain*.sh` run the whole stack. `TEST=skip` builds without the recipe tests.
- `athena-ref-amd64`: `almalinux:9`, `--platform linux/amd64`, with `athena-work-amd64` and
  `/cvmfs`: ATLAS's x86_64 release, for the x86_64 references
  (`/work/tmp/cvmfs-athena.sh` picks the architecture). Besides the EL9 packages listed above it
  needs `libpciaccess` (the x86_64 release links it). `/work/tmp/refs.sh` runs the layers'
  reference-checked tests in it.
- conda-forge's CI image has no `man`: CORAL and COOL needed a patch for that.

### osx-arm64 (M8), natively

- Under `_work/`: rattler-build in `_work/osx-tools`, the pinning (a copy of the containers')
  and `extra_variants.yaml` in `_work/osx-work`, which is `WORK` for `build-local.sh`.
  `CONDA_BUILD_SYSROOT` there is the MacOSX 11.0 SDK in `_work/sdks` (from
  github.com/phracker/MacOSX-SDKs, as conda-forge's CI uses): ROOT's interpreter fails on the
  mach headers of newer SDKs (README). Tests that run ROOT outside rattler-build need
  `SDKROOT` set to it.
  `_work/osx-try2.sh <recipe> ...` builds each recipe in turn and goes on after a failure, with
  a clean `PATH` (some Makefiles break on the spaces in the host's).
- A failed build leaves its tree in `_work/osx-work/output/bld`: `source build_env.sh` in its
  `work/` and `ninja -k 0` in its build directory lists every compile error at once.
- What macOS changes (see PLAN.md, M8):
  - dyld ignores `LD_LIBRARY_PATH`, and System Integrity Protection drops `DYLD_*` from the
    environment of every system executable (`/bin/bash`, `/usr/bin/env`, so every script with
    an `env` shebang). Libraries find each other through rpaths, and code that `dlopen`s a bare
    library name needs `@rpath/` (CORAL, ers, Gaudi's python).
  - Current macOS kills copies of system binaries (AtlasCMake copied `/bin/bash`):
    athena-externals requires conda-forge's bash there.
  - The ROOT-based recipes use clang 20, the compiler of conda-forge's ROOT 6.40
    (`variants.yaml`), and C++ code needs `-D_LIBCPP_DISABLE_AVAILABILITY`: conda-forge's
    libc++ 20 headers mark `std::from_chars` with an attribute that does not compile.
  - ROOT is 6.40.04 there (6.40.02, ATLAS's, elsewhere): 6.40.02's `TTreeIndex` loses the low
    bits of 64-bit keys where `long double` is `double`, and POOL cannot read most MC files.
  - Each macOS library has a private copy of the vtable of a class without a key function, and
    clang compiles a `dynamic_cast` to a final class as a vtable address comparison: Athena and
    Gaudi need `-fno-assume-unique-vtables` there (athena-externals' `conda-postconfig.cmake`).
  - conda-forge's ROOT (clang) raises FPEs that ATLAS's (gcc) does not: the tests check the
    logs for FPE warnings only on Linux. Apple silicon cannot trap FPEs and lldb needs
    developer mode: bisect with `fetestexcept(FE_INVALID)` checks instead.
  - CMake scans C++20 sources for modules, which needs clang-scan-deps: off everywhere.
  - Python imports only `.so` extensions, also on macOS; CMake's MODULE libraries are `.so`.
  - Use `sed -i.orig` (then remove the copy): GNU and BSD sed agree on no other `-i` form.

## Conventions

- Run `prek -a --quiet` before committing. Revert its changes to pre-existing upstream files
  (e.g. `.github/`).
- Conventional commits with an `Assisted-by: <harness>:<model>` trailer.
- Recipe maintainer is `ariostas`. Follow staged-recipes requirements: license files, sha256,
  no symlinks in noarch packages, tests.
- Never ship ATLAS's `authentication.xml` (it holds Oracle passwords) or anything from CVMFS
  whose licence is unclear.
