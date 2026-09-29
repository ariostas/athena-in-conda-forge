# Athena in conda-forge: prior art and related work

Research date: 2026-09-29. Sources: the GitHub API (`gh`), the public CERN GitLab API (projects, MRs, raw files), the anaconda.org API, the gitlab-registry.cern.ch API, Indico exports and slides, ATLAS docs, and `/cvmfs/atlas.cern.ch`. **Verified** means I read the repo, file, API response or CVMFS content myself. **Search-only** means the claim rests on a search-engine summary or a single page I did not cross-check. **Guess** is marked as such.

---

## TL;DR (decision-relevant)

1. **Someone has already built part of Athena against conda-forge: Chris Burr's proof of concept (Feb 2026).** Chris Burr is from CERN and LHCb, and is on conda-forge core.
   - Repos: [`cburr/atlas-conda`](https://gitlab.cern.ch/cburr/atlas-conda) and [`cburr/atlascmake-conda-package`](https://gitlab.cern.ch/cburr/atlascmake-conda-package). Matthew Feickert forked the latter.
   - It builds **AnalysisBase and ColumnarAnalysis** (not full Athena) from `athena/Projects/*` with **unmodified AtlasCMake plus 5 small patches, 12 conda Find modules and stub `*ExternalsConfig.cmake` files**. These replace AnalysisBaseExternals / AthAnalysisExternals / AthSimulationExternals / AthGenerationExternals.
   - It also needs 2 athena source patches: `_dlfcn_hook` / glibc and libxml2 ≥ 2.12.
   - Scope: linux-64 only, gcc 14.3, ROOT 6.36/6.38. Dormant since 2026-02-25.
   - **This is the closest template for our "native AtlasCMake" approach.** Coordinate with cburr.
2. **EP-SFT is building Athena outside CVMFS right now, with a different tool.** [`bitsorg/atlas.bits`](https://github.com/bitsorg/atlas.bits) (Predrag Buncic, Sep 2026, active).
   - It runs ATLAS's own `build_externals.sh` and `build.sh` **unchanged** on top of an LCG_110_ATLAS_5 closure built by `bits` (an aliBuild fork). A generated `LCG_externals_<platform>.txt` view satisfies `find_package(LCG 110 EXACT)`.
   - Where it has got to: AthenaExternals, with CORAL/COOL built in-project and Oracle stripped. On the Athena side, only a **12-package AthExHelloWorld subset** of Athena 25.0.70, pinned *"last tag before chai dep"*. x86_64-el9 only.
   - Its commit log is a list of concrete pitfalls, in §1.2.
3. **ATLAS already supports one non-LCG, non-CVMFS build: AnalysisBase.**
   - AnalysisBaseExternals builds its own ROOT, Boost, Python, TBB, XRootD, HDF5, onnxruntime and others.
   - atlasexternals CI builds it with **system gcc13 on Ubuntu 24.04** ([.gitlab-ci.yml](https://gitlab.cern.ch/atlas/atlasexternals/-/blob/main/.gitlab-ci.yml)).
   - AnalysisBase **used to build natively on macOS (x86_64, clang)** from about 2016 to 2023: ~25 macOS MRs by Attila Krasznahorkay and Nils Krumnack, the last in [athena!61147](https://gitlab.cern.ch/atlas/athena/-/merge_requests/61147) (2023-03).
   - There is **no macOS CI today**, and I found no evidence of any arm64-mac build. The full Athena project has **never** been built on macOS as far as I can find.
4. **Gaudi is on conda-forge, but only on Linux.**
   - [`gaudi-feedstock`](https://github.com/conda-forge/gaudi-feedstock) was created 2026-06-11; maintainer chrisburr; version 40.6; linux-64 and linux-aarch64 only. The recipe says *"Skip macOS for now due to lack of upstream support"*. It carries 2 patches, one of which is a plugin-registry fix for conda environments.
   - Upstream Gaudi now has the pieces a conda build needs:
     - macOS core and libc++ support: [!1883](https://gitlab.cern.ch/gaudi/Gaudi/-/merge_requests/1883) and [!1884](https://gitlab.cern.ch/gaudi/Gaudi/-/merge_requests/1884), in v40r3.
     - Relocatable plugin-path discovery: [!1925](https://gitlab.cern.ch/gaudi/Gaudi/-/merge_requests/1925), in v40r4.
     - A pixi dev environment: [!1955](https://gitlab.cern.ch/gaudi/Gaudi/-/merge_requests/1955), in v41r0.
     - Cross-platform test portability ([!1885](https://gitlab.cern.ch/gaudi/Gaudi/-/merge_requests/1885)) is still open.
   - **ATLAS uses its own fork** [`atlas/Gaudi`](https://gitlab.cern.ch/atlas/Gaudi). AthenaExternals 25.0.73 ships **Gaudi 40.4** (tags `v40r4.00x`), not conda-forge's 40.6. We will need our own `gaudi` build or output, or a variant of the conda-forge one.
5. **LHCb is already doing "Gaudi-based experiment stack as conda packages".**
   - [`clemenci/pixi-stack`](https://gitlab.cern.ch/clemenci/pixi-stack) (Marco Clemencic, Gaudi lead, Jul–Sep 2026) builds Gaudi, Detector and LHCb with rattler-build from a `pixi.toml`. It uses an extra `s3.cern.ch/lhcb-conda/channel`.
   - [`cburr/lhcb-conda-recipes`](https://gitlab.cern.ch/cburr/lhcb-conda-recipes) has DD4hep patches for runtime plugin-path auto-detection.
   - Chris Burr's HSF talk: *"LHCb will likely end up with a channel for their physics stack"*.
   - **Belle II** announced a move of its externals to conda-forge (HSF seminar, 2026-06-24), with ARM and macOS as the main driver.
6. **ATLAS's own distribution outside CVMFS is RPMs and containers.**
   - Containers come from [`atlas-sit/docker`](https://gitlab.cern.ch/atlas-sit/docker) and are published at `gitlab-registry.cern.ch/atlas/athena/{analysisbase,athanalysis,athgeneration,athsimulation,analysistop}`. They are built weekly for AnalysisBase and AthAnalysis.
   - The images `dnf install` the ATLAS release RPM, which pulls in LCG RPMs under `/opt/lcg`.
   - **`analysisbase:25.2.80` is a single-arch amd64 image** (verified from the registry manifest).
   - ATLAS Open Data tells outside users to run `setupATLAS -c gitlab-registry.cern.ch/atlas/athena/analysisbase:25.2.2`. **There is no native macOS or arm64 path for Open Data users.** This is the clearest demand signal for a conda AnalysisBase.
7. **aarch64 is well established in ATLAS; osx-arm64 is not.**
   - Athena aarch64 builds have been on CVMFS since **23.0.0 (aarch64-centos7-gcc11-opt)**. Today there are 86 el9-gcc13, 29 gcc14 and 8 gcc15 aarch64 Athena releases. The platform was physics-validated on AWS Graviton2 ([CHEP 2023, EPJ WoC 295 05019](https://www.epj-conferences.org/articles/epjconf/abs/2024/05/epjconf_chep2024_05019/epjconf_chep2024_05019.html)).
   - The atlasexternals CI builds all Externals projects on `aarch64-el9-gcc15`, and there are nightly clang builds (clang22 in CI; one `x86_64-el9-clang19-opt` Athena release exists on CVMFS).
   - **linux-aarch64 is low risk. osx-arm64 (clang + libc++ + Mach-O) is the real unknown** for full Athena.
8. **Nothing else exists.**
   - No Spack, Nix, Homebrew or conda package of Athena or AnalysisBase exists anywhere I looked (GitHub, CERN GitLab, anaconda.org, Spack builtin).
   - The names `athena`, `analysisbase`, `atlascmake` and `atlasexternals` are **free on conda-forge and bioconda**. `athena` is taken on PyPI (a Hadoop tool), and bioconda has `athena_meta`.
   - Closest non-conda prior art:
     - GeoModel/VP1Light Homebrew tap, [`GeoModelDev/packaging/homebrew-geomodel`](https://gitlab.cern.ch/GeoModelDev/packaging/homebrew-geomodel) (macOS, active to 2026-03).
     - Riccardo Bianchi's 2017 "build ATLAS software on your own SLC6 machine" blog, which still used LCG from CVMFS.
9. **There is a ready-made reviewer and ally network.**
   - The "HEP Packaging Coordination" project (Chris Burr, Matthew Feickert, Lindsey Gray, Giordon Stark) already lists ATLAS as a contributor.
   - ATLAS people maintain related feedstocks: kratsg (klfitter, fastframes, pyami-atlas, stare-atlas, voms-lsc, atlas-schema, rucio-mcp), matthewfeickert (lwtnn, klfitter, func-adl-xaod, servicex, spheno-atlas variant), gordonwatts (func-adl, servicex), and paulgessinger (acts).
   - `klfitter-feedstock` was **created 2026-02-13, the same day as the atlascmake POC**, with maintainers chrisburr, kratsg and matthewfeickert. This is evidence the POC already fed packages into conda-forge.
10. **License:** Athena and atlasexternals are *"released under the Apache 2.0 license, except where other licenses apply"* (top-level `LICENSE`, verified). The repo has been public since 2018-12-17 (Zenodo DOI 10.5281/zenodo.2641997). I did **not** do a per-file license scan; we need one before claiming plain `Apache-2.0` in `about.license`.

---

## 1. Prior packaging of ATLAS software outside CVMFS/LCG

### 1.1 `cburr/atlas-conda` + `cburr/atlascmake-conda-package` (Feb 2026, POC, dormant) — most relevant

Verified: I cloned both repos.

- **Goal** (README): *"Proof of concept using conda-forge as a base for athena"*. The stated assumptions are:
  - *"`ATLASExternals` would be dropped, with the versions being managed by a `pixi.toml`/`pixi.lock`"*.
  - *"`atlascmake` becomes a conda-package … that replaces `ATLASExternals`"*.
  - There would be *"one environment per project (e.g. `AnalysisBase`, `ColumnarAnalysis`) … in the same solve group"*.
- **pixi.toml:**
  - linux-64 only, `libc.version = "2.28"`.
  - Common dependencies: `gcc 14.3`, `cmake ≥4.2.3`, `root ≥6.36.6` with `root_cxx_standard = 20.*`, `python 3.14`, `libboost-devel 1.88–1.89`, `tbb-devel 2022`, `vdt`, `eigen`, `gmock`, `nanobind`, `libuuid`.
  - AnalysisBase feature adds: `fastjet`, `fastjet-cxx`, `fastjet-contrib`, `lhapdf`, `lwtnn`, `klfitter`, `onnxruntime-cpp 1.22`, `hdf5`.
  - The lock file resolves `root_base 6.36.08` and `6.38.00`. The README notes that the ROOT 6.38.0 update needed an AtlasCMake fix ([commit 981cd636](https://gitlab.cern.ch/cburr/atlascmake-conda-package/-/commit/981cd636d5a3bb581e33796e94c6636ece14c5d0)).
- **Build:** plain `cmake -S athena/Projects/AnalysisBase $CMAKE_ARGS -B build`, i.e. the native `atlas_project()` build. There is no custom CMake layer.
- **atlascmake recipe** (rattler-build, `noarch: generic`):
  - Takes `Build/AtlasCMake` from atlasexternals at a fixed commit and patches it with `apply_patches.py`:
    1. Stub `lcg_generate_env()`, which writes an empty `SH_FILE`.
    2. Force `CMAKE_INSTALL_LIBDIR` back to `lib`. Conda's `$CMAKE_ARGS` plus CMake 4 turn it absolute, which yields `build/<platform>/home/.../lib`.
    3. Bridge `ROOT_genreflex_CMD` / `ROOT_rootcling_CMD` → `ROOT_*_EXECUTABLE`. These are normally set by `LCGFunctions.cmake`.
    4. Add `ATLASCMAKE_MODULEDIR` and `PROJECT_ROOT` to `CMAKE_FIND_ROOT_PATH`. Conda's toolchain sets `CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY`, which breaks AtlasCMake's `find_file()` of skeletons.
    5. `atlas_os_id()` → `"cf"`, so platform strings look like `x86_64-cf-gcc14-opt`.
  - 12 Find modules. The most important is **`FindROOT.cmake`**, which rewrites the component lists that ATLAS packages pass:
    - drops `Cint` and `pthread`;
    - maps `Math` → `MathCore`;
    - makes `PyROOT`, `cppyy` and `CPyCppyy` optional (`CPyCppyy` → `ROOTPythonizations`);
    - finds VDT separately;
    - then forwards to `ROOTConfig.cmake`.
    - *"178 packages list pthread as ROOT component"*.
    - The others bridge Eigen, FastJet, FastJetContrib, GMock, KLFitter, Lhapdf, TBB, UUID, VDT, lwtnn and onnxruntime to AtlasCMake's `*_INCLUDE_DIRS` / `*_LIBRARIES` conventions.
  - Stub `AnalysisBaseExternalsConfig.cmake` and friends:
    - load AtlasCMake plus ROOT;
    - `link_libraries(Threads::Threads)`, because the conda sysroot needs explicit `-lpthread`;
    - `cmake_policy(SET CMP0167 OLD)`, because CMake 4 removed FindBoost.
- **Athena source patches:**
  1. `Control/CxxUtils/src/AthDsoCbk.c`: always use the static `_dlfcn_hook`. The conda sysroot has glibc 2.17 headers, so `__GLIBC_PREREQ(2,34)` is false at compile time, but the runtime glibc lacks the symbol.
  2. `DataQuality/GoodRunsLists/Root/TGoodRunsListWriter.cxx`: libxml2 ≥ 2.12 API.
- **How far it got** (verified from the README and the lock file): AnalysisBase and ColumnarAnalysis configure, build and install. The README gives no information about tests or runtime validation. Last commit 2026-02-25.
- **Lessons:**
  - The AtlasCMake-native approach works with a *thin* shim. Build on it rather than rewriting CMake.
  - Put the shim upstream in atlasexternals: Chris suggests *"a `pixi.toml` file could be added to the main `atlascmake` sources"*.
  - The `CMAKE_INSTALL_LIBDIR`, `CMAKE_FIND_ROOT_PATH_MODE_*`, CMP0167, pthread-component and glibc-2.17-sysroot issues will all recur for full Athena.
  - Re-check the `_dlfcn_hook` issue against whatever `c_stdlib_version` (sysroot) we build with (guess: a newer sysroot may make the patch unnecessary).

### 1.2 `bitsorg/atlas.bits` (Sep 2026, EP-SFT, active)

Verified: README, recipes and the full commit log.

- **Context.** `bits` is *"Re-branded and extended aliBuild"*, proposed by Predrag Buncic (EP-SFT) as a common build tool for LHC experiments. It was presented at the [Joint Experiment Meetings, 2025-02-06](https://indico.cern.ch/event/1501541/contributions/6356807/): *"we need at least two experiments to sign up"*.
  - The org has `lcg.bits` (~1100 recipes), `stacks.bits`, `alice.bits`, `lhcb.bits`, `key4hep.bits`, `cms.bits`, `ship.bits` and `atlas.bits`, plus a `bits → CVMFS` publisher (`cvmfs-bits`) and a `homebrew-system-deps` repo (so macOS is at least intended).
- **Approach.**
  - `lcg-view` emits `LCG_110_ATLAS_5/LCG_externals_<platform>.txt` whose `dir` fields point at bits install prefixes. With that, ATLAS's `AtlasLCG/LCGConfig.cmake` resolves everything with no symlink farm.
  - `atlasexternals.sh` runs `Projects/Athena/build_externals.sh`, and `athena.sh` runs `Projects/Athena/build.sh`.
  - Network is allowed during the build, because `build_externals.sh` clones atlasexternals and downloads the Gaudi, ACTS, GeoModel and vecmem tarballs.
  - The `defaults-atlas.sh` overlay records the `_ATLAS_5` deltas relative to base LCG_110:
    - generator pins (`madgraph5amc 3.5.11.atlas16`, `epos4 4.0.3.atlas3`, `hijing …atlas20260625`, `tauolacpp atlas1`, `pythia6 429.2`, `sherpa 3.0.4`, `xrootd 6.1.1`);
    - CUDA 13.3.1 / cuDNN 9.20;
    - disabled LCG packages: `DD4hep`, `acts` (*"AthenaExternals builds its own ACTS"*), `onnxruntime`, `R`, `rpy2`, `tf2onnx`.
- **How far it got:**
  - AthenaExternals builds, with a custom package filter that adds `External/CrestApi`.
  - Athena builds **only the AthExHelloWorld closure**: CxxUtils, AthContainers, AthLinks, AthenaKernel, SGCore, StoreGate, AthenaBaseComps, CLIDComps, xAODCore, xAODEventInfo, PersistentDataModel, RootUtils and a few more.
  - Pinned to `release/25.0.70`.
  - No full Athena, no tests, x86_64-el9 only.
- **Pitfalls recorded in the commit log** (all verified, and all apply to us):
  - *"Base LCG 110 no longer ships the legacy CORAL/COOL conditions stack"*. They build them in-project with `-DATLAS_BUILD_CORAL=ON -DATLAS_BUILD_COOL=ON` and patch out:
    - **`OracleAccess`**, which needs the non-redistributable Oracle Instant Client;
    - **`CORAL_SERVER`**, which needs Sun RPC `rpc/rpc.h`, removed from glibc.
    - *"Athena uses only CORAL RelationalAccess + the SQLite/Frontier backends"*.
  - Athena `release/25.0.70` was chosen as the *"last tag before chai dep"*. **CHAI** is a new CREST conditions client from [`crest-db/chai`](https://gitlab.cern.ch/crest-db/chai), built as `External/CHAI` in atlasexternals (verified). In 25.0.73 `Athena::CoralUtilitiesLib` links `chai::container` (verified in `AthenaConfig-targets.cmake`). **We need CHAI + CrestApi recipes.**
  - *"athena 25.0.70 uses std::print (C++23); AtlasCompilerSettings enables C++23 only for gcc>=15"*. atlasexternals [!1403](https://gitlab.cern.ch/atlas/atlasexternals/-/merge_requests/1403): *"Use C++20 as default and C++23 for gcc15/clang22"*. So our ROOT must be the conda-forge `cxx23` variant, or we force C++23.
  - The ExternalProject install step `cmake -E copy_directory` into the shared platform dir **is not concurrency-safe** (flake8_atlas and PyModules race). They run the superbuild with `-j1`.
  - `PIP_ROOT` in the environment hijacks `pip install --user` inside `PyModules`. They unset it.
  - `build_project_externals.sh` forces `en_US.UTF-8` when the locale is `C` or unset. Set `LANG=LC_ALL=C.UTF-8`.
  - Python must be a *runtime* dependency, because AthenaExternals links libpython (Gaudi, confdb2). Otherwise the host libpython gets bound.
  - The platform string `LCG_PLATFORM` must match what AtlasCMake detects (`x86_64-el9-gcc15-opt`). Mismatches make `find_package(LCG)` silently fail with `LCG_FOUND FALSE`.
- **Lessons:**
  - bits takes the "keep LCG semantics, replace the delivery" route. We take the "drop LCG, use conda-forge" route, as cburr did.
  - bits' list of what AthenaExternals still builds itself is our list of recipes to write: Gaudi, ACTS, GeoModel, vecmem, CORAL/COOL, CrestApi, CHAI, yampl, prmon, and the rest.
  - EP-SFT is actively interested in ATLAS-outside-CVMFS. Tell Buncic, to avoid duplicated effort.

### 1.3 ATLAS's own non-LCG build: AnalysisBase

- **AnalysisBase is the exception.** Elmsheuser, [Joint Exp. Meeting 2025-02-06](https://indico.cern.ch/event/1501541/contributions/6351642/): *"Full stand-alone ROOT based release (no LCG and tdaq dependencies) … Can be used via CVMFS and also with containers on e.g. a laptop"*. Athena, AthSimulation, AthGeneration, AthAnalysis and DetCommon use LCG, and Athena and DetCommon also use tdaq/tdaq-common.
- **AnalysisBaseExternals package list** ([package_filters.txt](https://gitlab.cern.ch/atlas/atlasexternals/-/blob/main/Projects/AnalysisBaseExternals/package_filters.txt), verified): HDF5, BAT, Blas, Boost, Davix, dcap, Eigen, lwtnn, FastJet, FastJetContrib, GoogleTest, KLFitter, Lhapdf, LibXml2, onnxruntime, nlohmann_json, PyAnalysis, PyModules, Python, ROOT, SQLite, TBB, XRootD.
  - Its CMakeLists sets `LCG_VERSION_NUMBER 0`: it *"set[s] up the AtlasLCG modules, without setting up an actual LCG release"*.
- **Ubuntu CI** (verified in [.gitlab-ci.yml](https://gitlab.cern.ch/atlas/atlasexternals/-/blob/main/.gitlab-ci.yml)): the job `build:x86_64-ubuntu2404-gcc13` builds `AnalysisBaseExternals` with Ubuntu's own `g++` (only CMake from ALRB). So ATLAS does keep one non-LCG, non-EL configuration green.
  - The other CI jobs: el9-gcc15 (all projects), el10-gcc15, el9-clang22 (AthenaExternals with `-DLCG_PLATFORM=x86_64-el9-gcc15-opt`, i.e. clang on top of the gcc LCG layer), and aarch64-el9-gcc15 (all projects).
- **macOS history** (verified from MR titles and descriptions):
  - atlasexternals, 2017–2020, all by akraszna: !93, !107, !172, !252 (*"Made CPack only generate TGZ files on MacOS by default. As that will be the format that we'll use to distribute central MacOS builds"*), !557 (Catalina), !621/!622/!624/!634, !737, !772 (Big Sur: *"I only tested this on x86. Since I won't be getting an ARM … Mac just yet, any updates necessary for those will have to come from someone else"*), !777 (HDF5), !788 (XRootD).
  - athena: !27697, !30684, !31362 (21.2), then !33415, !36641, !39414, !39513 (master, 2020–21, krumnack and akraszna), then [!61147](https://gitlab.cern.ch/atlas/athena/-/merge_requests/61147) (2023-03-01, krumnack: *"add 'fixes' to make AnalysisBase compile natively on MacOS … disable some things that xcode doesn't seem to support"*). That was the last one.
  - Platform strings like `x86_64-mac1013-clang90-opt` (AnalysisBase 21.2.24) and `x86_64-mac1015-clang12-opt` show up in user reports (search-only).
  - AtlasCMake still has `if(APPLE)` branches: `atlas_os_id` → `mac<maj><min>`, ctest wrappers.
  - No macOS CI job exists today. **Guess:** the AnalysisBase macOS build has bit-rotted since 2023, and none was ever done on arm64.
- **Lessons:**
  - AnalysisBase is the natural first milestone: no LCG, no tdaq, no Gaudi, and a historic macOS port.
  - krasznaa and krumnack are the people who know the macOS pitfalls.
  - The `ColumnarAnalysis` project (in `athena/Projects/`, uses `AnalysisBaseExternals`) is an even smaller target, and cburr built it too.

### 1.4 Containers and RPMs (ATLAS's official "no CVMFS" path)

- The Dockerfiles live in [`atlas-sit/docker`](https://gitlab.cern.ch/atlas-sit/docker), in the `analysisbase/`, `athanalysis/`, `athena/`, `athgeneration/` and `*-atlasos` directories.
  - The AnalysisBase image is `yum -y install ${PROJECT}_${RELEASE}_${PLATFORM}`, i.e. the release RPM plus LCG RPMs.
  - The Athena Dockerfile has `base-amd64` / `base-arm64` stages, so it can produce aarch64 images. The default `BINARY_TAG=${ATLAS_ARCH}-centos7-gcc11-opt` is stale.
- Registry: `gitlab-registry.cern.ch/atlas/athena/analysisbase` has 1266 tags and `athanalysis` 1236. Docker Hub `atlas/analysisbase` and `atlas/athanalysis` were last updated 2023-02, with about 14M pulls each.
  - I checked `analysisbase:25.2.80` (2026-01-15): **amd64-only OCI manifest**, config `ANALYSISRELEASE=AnalysisBase_25.2.80_x86_64-el9-gcc14-opt`, ~1.1 GB compressed.
- Elmsheuser 2025: *"Containers: Created for AnalysisBase/AthAnalysis every week; created on demand for other releases occasionally"*.
- The ATLAS docs for Ubuntu ([ubuntu-setup](https://atlas-software.docs.cern.ch/athena/containers/ubuntu-setup/)) use Docker plus a host CVMFS mount. The [build guide](https://atlas-software.docs.cern.ch/athena/developers/building/) says: *"A full Athena build needs access to CVMFS, AFS and EOS … CVMFS is a very strong requirement. It's not impossible to build Athena without it, but it certainly requires expert level knowledge"* and *"it's still possible to install from e.g. RPMs but this is not yet covered in these instructions"*.
- **Lesson:** on Apple Silicon, Open Data users run an amd64 image under emulation. A native osx-arm64 AnalysisBase conda package is a concrete improvement to pitch.

### 1.5 Manual or standalone builds

- Riccardo M. Bianchi, ["Building the ATLAS software on your own SLC6 machine"](https://www.riccardomariabianchi.com/building-the-atlas-software-on-your-own-SLC6-machine.html) (2017-08-11): AthenaExternals plus Athena built with `build_externals.sh`, still using **LCG from CVMFS**.
  - Problems he hit: system Eigen shadowing LCG's, missing `expat.h`, missing `makeinfo`, GeoPrimitives template errors.
  - Lesson: **isolate from host packages**, which rattler-build does for us.
- VP1Light / GeoModel on macOS through Homebrew:
  - [`GeoModelDev/packaging/homebrew-geomodel`](https://gitlab.cern.ch/GeoModelDev/packaging/homebrew-geomodel), `brew tap atlas/geomodel`, formulas at GeoModel 6.25.0 (2026-03).
  - [`ric-bianchi/homebrew-vp1light`](https://github.com/ric-bianchi/homebrew-vp1light), dormant since 2019.
  - This is the only ATLAS-maintained macOS binary distribution I found.
- `dguest/analysisbase-docker` (2019), `matthewfeickert/atlas-analysisbase-dask-environment` (2023) and [`usatlas/analysisbase-dask`](https://github.com/usatlas/analysisbase-dask) (AnalysisBase 24.2 + dask + Scikit-HEP for the UChicago AF, pushed 2026-09) all layer pip packages on the official images. That is more evidence of demand for AnalysisBase and Python together.

### 1.6 ARM (aarch64) history

- CVMFS (verified with `ls`): the first aarch64 Athena releases are **23.0.0–23.0.14, `aarch64-centos7-gcc11-opt`**, followed by 86 `aarch64-el9-gcc13`, 29 gcc14 and 8 gcc15 releases. AnalysisBase has had aarch64 builds since 25.2.x (`aarch64-el9-gcc13-opt`).
- Enabling MRs: atlasexternals [!803](https://gitlab.cern.ch/atlas/atlasexternals/-/merge_requests/803) *"ARM64 Link Page Alignment Adjustment"* (2021-01) and [!867](https://gitlab.cern.ch/atlas/atlasexternals/-/merge_requests/867) *"CORAL/COOL Fixes for ARM64"* (2021-09). athena: several ssnyder CxxUtils aarch64 MRs in 2021–2022, and `ElectronPhotonFourMomentumCorrection` aarch64 unit-test fix [!89160](https://gitlab.cern.ch/atlas/athena/-/merge_requests/89160) (2026-06).
- Paper: *"The ATLAS experiment software on ARM"*, CHEP 2023 ([EPJ WoC](https://www.epj-conferences.org/articles/epjconf/abs/2024/05/epjconf_chep2024_05019/epjconf_chep2024_05019.html), [PDF](https://indico.jlab.org/event/459/papers/11553/files/844-CHEP_2023_ATLAS_ARM.pdf)).
  - It reports full physics validation of reconstruction and G4 simulation on AWS Graviton2.
  - It reports that ARM *"is fully integrated in the regular software build system"* (search-only summary).
  - An earlier CHEP 2016 paper, "ATLAS software stack on ARM64", also exists.
- Build farm (Undrus, 2025-02): 18 × 64-core Alma9 bare-metal nodes, 10 × 16-core VMs, **4 × 20-core ARM VMs**. There are about 30,000 builds per year. Athena is about 2000 packages with about 2400 CTest unit tests.

### 1.7 Spack, Nix, Homebrew, pixi

- **Spack:** no Athena or AnalysisBase package. Spack's `athena` is an unrelated code and `atlas` is the linear-algebra library.
  - Spack builtin does have ATLAS-relevant externals: `coral` and `cool` 3.3.10, `frontier-client` 2_9_1, `gaudi` 40.5 (maintainers drbenmorgan, vvolkl, jmcarcell), `geomodel` 6.31.0, `acts` 46.8.1, `lwtnn`, `prmon` (graeme-a-stewart, amete), `heppdt`.
  - These are useful as build-recipe references for the packages missing on conda-forge (CORAL, COOL, frontier_client).
  - I found no ATLAS Spack evaluation, public or otherwise (search-only; ATLAS JIRA is not public).
- **Nix:** nothing ATLAS-related.
- **Homebrew:** only GeoModel/VP1Light (§1.5).
- **pixi:** cburr's POC (§1.1) and Gaudi's own `pixi.toml` ([!1955](https://gitlab.cern.ch/gaudi/Gaudi/-/merge_requests/1955)).

---

## 2. Gaudi, Key4hep and other Gaudi-based stacks

### 2.1 conda-forge `gaudi`

- History: staged-recipes [#31883](https://github.com/conda-forge/staged-recipes/pull/31883) was opened 2026-01-09 and is still open (superseded). [#33620](https://github.com/conda-forge/staged-recipes/pull/33620) was merged 2026-06. The feedstock was created 2026-06-11, gained linux-aarch64 on 2026-06-13, and is now at **40.6**. The only maintainer is **chrisburr**.
- Recipe highlights (verified):
  - `skip: osx` and `win`, and Python < 3.13 (*"conda-forge Python lacks gdbm support, so dbm.sqlite3 (Python 3.13+) is needed for confdb2"*).
  - `-DGAUDI_DEFAULT_PLUGIN_PATH=$PREFIX/lib`, `-DGAUDI_INSTALL_PYTHONDIR=$SP_DIR`, `-DCMAKE_CXX_SCAN_FOR_MODULES=OFF`.
  - Runs the **full ctest suite** in the build, with `--repeat until-pass:3` for flaky tests, excluding 2 tests.
  - `run_exports: pin_subpackage(gaudi, upper_bound="x.x.x")`.
  - Host dependencies: root_base, root_cxx_standard, boost + boost-python, tbb, range-v3, fmt, nlohmann_json, clhep, xerces-c, catch2, ms-gsl, aida, heppdt, zstd, libuuid.
  - Patches: (1) a follow-up to Gaudi !1925, so `Registry::initialize()` also scans the default plugin path (upstream [!1943](https://gitlab.cern.ch/gaudi/Gaudi/-/merge_requests/1943) was *closed*, not merged); (2) the pytest 9 `startdir` hook.
- **For us:**
  - ATLAS pins `atlas/Gaudi` v40r4.00x. AthenaExternals 25.0.73 reports Gaudi `PACKAGE_VERSION "40.4"`, and the atlas/Gaudi fork has tags `v40r4`, `v40r4.001` and `v40r4.002` (2026-05/06).
  - Options:
    - (a) build `atlas/Gaudi` as our own output (`gaudi-atlas` or inside the athena recipe);
    - (b) ask for an ATLAS variant in gaudi-feedstock;
    - (c) check whether ATLAS's patches are all upstream in 40.6. Not checked; the `v40r4.00x` diffs vs `v40r4` need a look.
  - macOS Gaudi is upstream since v40r3 but untested on conda-forge. The test-portability MR !1885 is still open.

### 2.2 Upstream Gaudi conda and macOS work (verified MR list)

- [!1925](https://gitlab.cern.ch/gaudi/Gaudi/-/merge_requests/1925) (clemenci, v40r4): plugin path derived with `dladdr` relative to `GaudiPluginService`. *"In Conda … the plugin directory is typically **not** on `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH`"*.
- [!1883](https://gitlab.cern.ch/gaudi/Gaudi/-/merge_requests/1883) and [!1884](https://gitlab.cern.ch/gaudi/Gaudi/-/merge_requests/1884) (cburr, v40r3), "macOS core system support" and "libc++ compatibility":
  - Mach timing and memory APIs, lldb stack traces;
  - type-name normalisation for libc++;
  - `std::vector<bool>` toStream, libc++ float parsing in RootNTupleCnv;
  - disabled `std::format` tests for libc++ < 19.
- Earlier macOS MRs: akraszna 2016–2019, mato 2017–2020, vavolkl 2020–2023 (`GAUDI_LIBRARY_PATH` instead of `LD_…` on macOS).
- Other cburr fixes in the same period: fmt 11 compatibility (!1871), `std::_Bit_reference` dictionary removal (!1901), bash env scripts (!1877).
- **Lessons:**
  - Athena's own plugin and component loading (the Gaudi PluginService, `*.components`, `*.confdb2`, the ROOT `.rootmap`/`.pcm` files, and ATLAS's `ATLAS_*` search paths) will hit the same "not on `LD_LIBRARY_PATH`" problem. Expect to set `LD_LIBRARY_PATH`-free search paths through activation scripts, or to patch.
  - libc++ issues in Gaudi (RTTI string comparison, type names) will reappear in Athena's own `System::typeinfoName` users and in ROOT dictionaries.

### 2.3 LHCb stack as conda packages (2026)

- [`clemenci/pixi-stack`](https://gitlab.cern.ch/clemenci/pixi-stack) (Jul–Sep 2026):
  - Uses rattler-build `--up-to lhcb` on source trees checked out with `lb-ci checkout`, plus sccache.
  - Builds DD4hep locally, *"because the default conda-forge version is not built with Geant4 units"*.
  - Noted limitations:
    - data packages are located by environment variables;
    - there is no per-project Debug/Release control;
    - *"we have to force Detector to use `-march=x86-64-v2` while Conda selects by default `-march=nocona`"*.
  - linux-64 only. Uses channel `https://s3.cern.ch/lhcb-conda/channel` on top of conda-forge.
- [`cburr/lhcb-conda-recipes`](https://gitlab.cern.ch/cburr/lhcb-conda-recipes) (2026-03), DD4hep and simple_conddb_cxx recipes. The DD4hep patches:
  - auto-detect the C++ standard from ROOT;
  - remove the Geant4 C++ standard check;
  - preload libpython for listcomponents on macOS;
  - auto-detect the plugin search path and `DD4hepINSTALL` at runtime;
  - drop the `DD4HEP_LIBRARY_PATH` requirement.
  - simple_conddb_cxx: `-Wl,--no-undefined` is Linux-only. This is probably relevant to us. **Guess, not verified:** AtlasCMake may add similar `--no-undefined`-style link flags on Linux, which macOS ld64 does not accept.
- **Lessons:**
  - "Gaudi-based experiment stack on conda" is being actively prototyped by the Gaudi maintainer himself.
  - Relocatable plugin discovery is the recurring theme.
  - x86-64 microarchitecture flags differ (conda-forge targets `nocona`, ATLAS targets x86-64-v2). Check that ATLAS code does not assume SSE4 or AVX without runtime dispatch.

### 2.4 Key4hep, FCCSW, LCG on macOS

- Key4hep (Carceller, [HSF seminar 2026-06-24](https://indico.cern.ch/event/1692605/contributions/7148115/)):
  - More than 600 packages. Built with **Spack** (key4hep-spack, about 85 non-upstream recipes) and **now also inside LCG stacks** (the `--lcg` opt-in).
  - Supports Alma9, Ubuntu 24.04 and Ubuntu 26.04. **No conda.**
  - LCGCMake builds *"over 70 builds every day … (x86_64, aarch64, arm64 for Mac)"*. **LCG does produce macOS arm64 stacks**, but ATLAS does not use them. **Guess:** some LCG macOS patch sets for ROOT, Geant4 and similar may be reusable references.
- I found no evidence of an "FCCSW in conda" effort (search-only). Early FCCSW used LCG and later Spack.
- `hep-forge` ([anaconda.org/hep-forge](https://anaconda.org/hep-forge), [github.com/hep-forge](https://github.com/hep-forge)) is a separate community channel with 82 packages (pheno and EIC: podio 1.7, edm4hep 1.0, acts 46.8.1, dd4hep, herwig7, sherpa…), linux-64 and linux-aarch64 only. It is not ATLAS-related and not conda-forge, and it ships a `root-guard` to stop conda-forge ROOT being mixed in. Treat it as a warning about channel fragmentation, not as a dependency.

---

## 3. conda-forge feedstocks for ATLAS-adjacent software (verified 2026-09-29)

"ATLAS 25.0.73" is the version in AthenaExternals or LCG_110_ATLAS_5 (from CVMFS `*ConfigVersion.cmake`, `ReleaseData`, and the atlas.bits overlay).

| Package (conda-forge) | cf latest | Platforms with latest | ATLAS 25.0.73 | Maintainers | Notes |
|---|---|---|---|---|---|
| gaudi | 40.6 | linux-64, linux-aarch64 | 40.4 (atlas/Gaudi fork) | chrisburr | no osx |
| acts-core | 45.5.1 | linux, osx | **47.7.0** | paulgessinger, matthewfeickert | ATLAS builds its own; cf lags by 2 majors |
| geomodel(-core,…) | 6.31.0 | **linux-64 only** | 6.29.0 | olantwin (SHiP) | created 2026-06-21 |
| vecgeom | 2.0.0 | linux, osx | **1.1.21** | utk4r-sh et al. | major-version mismatch |
| geant4 | 11.4.2 | linux, osx | ATLAS builds its own (atlasexternals) | chrisburr, tkittel | cf is C++17, no VecGeom (per the CMSSW notes) |
| lwtnn | 2.14.2 | linux, osx, ppc64le | yes | matthewfeickert | created 2026-01-22 |
| onnxruntime-cpp | 1.30.0 | linux, osx-arm64 | 1.24.2 (atlasexternals [!1383](https://gitlab.cern.ch/atlas/atlasexternals/-/merge_requests/1383)) | xhochy, hmaarrfk, … | |
| prmon | 3.3.0 | linux only | yes | chrisburr | |
| xrootd | 6.1.1 | linux, osx | 6.1.1 | chrisburr | |
| klfitter | 1.5.0 | linux, osx | AnalysisBase | chrisburr, kratsg, matthewfeickert | created 2026-02-13 for the POC |
| lcg-relax | 6.1.2 | linux-64, osx-64 | RELAX in LCG | chrisburr | no aarch64 or osx-arm64 |
| heppdt | 2.06.01 | linux, osx | yes | chrisburr | |
| hepmc3, clhep, fastjet(-cxx/-contrib), lhapdf, coin3d, soqt6, davix, highfive, ms-gsl, range-v3, xerces-c, nlohmann_json, gperftools, tbb-devel, libboost-devel | — | all 3 target platforms | | mixed | |
| libunwind | 1.8.3 | **linux only** | | | macOS has its own unwinder |
| **missing on conda-forge** | frontier_client (a personal channel `zhenxieit` has 2.8.20), CORAL, COOL, CrestApi, CHAI, yampl, tdaq/tdaq-common, `cppgsl` under that name (`ms-gsl` exists), APTypes, dSFMT, triSYCL, itksw-endec, hgtd-decoder, simage, vecmem, detray, traccc, covfie, actsvg | | | | Spack has coral, cool and frontier-client recipes |

- Also on conda-forge and ATLAS-relevant: `func-adl-xaod` and `func_adl_servicex_xaodr25` (gordonwatts, matthewfeickert), `servicex`, `atlas-schema` (kratsg, a coffea schema for ATLAS PHYSLITE / CNT), `fastframes` (kratsg, p-queue; staged-recipes #30548 *"feat: Add fastframes from ATLAS Experiment"*), `pyami-atlas`, `stare-atlas`, `voms-lsc`, `rucio-mcp`, `atlas-mc-scanner`, `spheno` with an ATLAS-patched `spheno-atlas` variant (a precedent for experiment-patched variants from one feedstock).
- On PyPI only (not conda-forge): `atlasify` 0.8.0, `atlas-mpl-style` 0.25.0, `puma-hep` 0.5.5, `atlasopenmagic` 1.10.1.

---

## 4. Demand signals and who would use it

- **ATLAS Open Data for research** (PHYSLITE, first released 2024-07):
  - [Containers page](https://opendata.atlas.cern/docs/tutresearch/containers) recommends `./setupATLAS -c gitlab-registry.cern.ch/atlas/athena/analysisbase:25.2.2`.
  - The [derivation framework](https://opendata.atlas.cern/docs/tutresearch/derivation_framework) (`physlitetoopendata`) is a C++ AnalysisBase framework distributed as Docker images.
  - Their tutorials otherwise use uproot, coffea and awkward to read PHYSLITE directly ([notebooks](https://github.com/atlas-outreach-data-tools/notebooks-collection-opendata)).
  - A conda AnalysisBase with `pixi add analysisbase` on osx-arm64 would remove the Docker, x86-emulation step for external users.
- **Analysis facilities:** UChicago AF ships AnalysisBase plus dask in a container ([usatlas/analysisbase-dask](https://github.com/usatlas/analysisbase-dask)).
- **Python and columnar direction inside ATLAS:**
  - `ColumnarAnalysis` project, [`krasznaa/atlas-tool-example`](https://github.com/krasznaa/atlas-tool-example) (*"dual/triple-use tools … Athena, EventLoop and 'any kind of' columnar analysis"*), `krasznaa/atlas-rdf-examples`.
  - These want ATLAS CP tools importable next to the Scikit-HEP stack, which is exactly what conda-forge solves.
- **Other experiments moving the same way:** LHCb (most non-physics software is already on conda-forge; the physics stack is being prototyped), Belle II (externals moving to conda-forge, GSoC 2026 ARM project), CMS (`cms-combine` on conda-forge; see the CMSSW notes).
- **HEP Packaging Coordination** ([org](https://github.com/hep-packaging-coordination), [HSF seminar slides](https://github.com/chrisburr/chrisburr-talks/tree/main/2026-06-24-hsf-conda-forge), [Feickert CHEP 2026](https://matthewfeickert-talks.github.io/talk-chep-2026/)): *"120+ HEP packages"*; *"Ongoing work is also supporting builds of LHCb experiment software and distributions of community software with experiment-specific patches applied for use in LHC physics analyses."* ATLAS appears only as a contributor of analysis-level packages, not the offline stack.
- **CVMFS delivery of conda envs** is being solved in parallel: Chris Burr's RattlerFS / `/cvmfs/conda-cache.cern.ch/prototype-v2/{linux-64,noarch,osx-arm64}` ([talk](https://github.com/chrisburr/chrisburr-talks/tree/main/2026-09-21-leaps-rattlervfs-cvmfs)), and LHCb's `lb-conda` locked environments on CVMFS. This matters if ATLAS asks "how does this reach the grid?".

---

## 5. People (potential allies and reviewers)

| Who | Role | Why relevant |
|---|---|---|
| Chris Burr (`chrisburr`, `cburr`) | CERN/LHCb, conda-forge core | Author of the atlas-conda POC, gaudi-feedstock, root/geant4/xrootd/prmon feedstocks, Gaudi macOS MRs |
| Matthew Feickert (`matthewfeickert`) | UW-Madison, ATLAS/IRIS-HEP, staged-recipes reviewer | Forked atlascmake-conda-package; lwtnn and klfitter feedstocks |
| Giordon Stark (`kratsg`) | UCSC, ATLAS | klfitter, fastframes, atlas-schema, pyami-atlas feedstocks |
| Gordon Watts (`gordonwatts`) | UW, ATLAS | func-adl-xaod, servicex feedstocks |
| Paul Gessinger (`paulgessinger`) | CERN, ACTS/ATLAS | acts feedstock |
| Marco Clemencic (`clemenci`) | CERN/LHCb, Gaudi lead | pixi-stack, Gaudi !1925 and !1955 |
| Attila Krasznahorkay (`akraszna`/`krasznaa`) | CERN, ATLAS core software | AtlasCMake author, all macOS atlasexternals work |
| Nils Krumnack (`krumnack`) | ATLAS analysis software | AnalysisBase macOS fixes, columnar tools |
| Johannes Elmsheuser, Frank Winklmeier, Alex Undrus | ATLAS ASCIG / release coordination | Own externals, platforms (aarch64, clang), nightlies |
| Predrag Buncic | CERN EP-SFT | bits / atlas.bits, in parallel |
| Oliver Lantwin (`olantwin`) | SHiP | geomodel feedstock (linux-64 only) |

---

## 6. Licensing

- `athena/LICENSE`, verified: *"The software in this repository is released under the Apache 2.0 license, except where other licenses apply."* `atlasexternals/LICENSE` has identical wording. The repo was made public on 2018-12-17 ([ATLAS news](https://atlas.cern/updates/news/open-software-release)), and the Zenodo record for 22.0.1 (2019) lists Apache-2.0.
- The installed release ships `InstallArea/<platform>/LICENSE.txt`. AthenaExternals also ships `LICENSE.onnxruntime` and `ThirdPartyNotices.onnxruntime`.
- **Not verified:** the "except where other licenses apply" files inside athena, for example vendored third-party code, generator interfaces, or data files with separate terms. A grep over the CVMFS `src/` tree timed out.
- **Action:** run `scancode`/`licensee` on the release tarball and list the exceptions in `about.license` (e.g. `Apache-2.0 AND …`) plus `license_file:`.
- Oracle Instant Client (CORAL OracleAccess) is **not redistributable**, so it must be dropped, as atlas.bits does.

---

## 7. Concrete lessons for our effort

1. **Reuse cburr's AtlasCMake shim instead of inventing one.** Package `atlascmake` (from atlasexternals `Build/AtlasCMake`, plus `AtlasLCG` if needed) as its own output, with his 5 patches, Find modules and `*ExternalsConfig.cmake` stubs, then extend it for `AthenaExternals`. Offer the shim upstream to atlasexternals; Chris suggested adding a `pixi.toml` there.
2. **Milestones in order of risk:**
   1. AnalysisBase on linux-64, reproducing the POC with current versions.
   2. AnalysisBase on linux-aarch64, which ATLAS already supports.
   3. AnalysisBase on osx-arm64, reviving the 2016–2023 macOS work.
   4. AthAnalysis, which adds Gaudi.
   5. Athena on Linux.
   6. Athena on osx-arm64.
3. **Gaudi:** ATLAS needs the atlas/Gaudi v40r4.00x fork. The conda-forge feedstock is 40.6, Linux-only, with conda plugin-path fixes. Diff atlas/Gaudi against upstream before deciding between our own output and a feedstock variant. For macOS, start from Gaudi ≥ v40r3 and expect to carry !1885-style test fixes.
4. **Externals that ATLAS builds itself** (bits' filter list plus CVMFS), and how we will get each:
   - Build ourselves or write new feedstocks: Acts 47.7, GeoModel 6.29, VecGeom 1.1.21, vecmem 1.27, detray 0.111, traccc 1.6, actsvg 0.4.51, CrestApi, CHAI, CORAL/COOL (no Oracle, no CORAL_SERVER), yampl, APTypes, dSFMT, itksw-endec, hgtd-decoder, boost-mpi3, triSYCL, and Geant4 (ATLAS-patched).
   - Take from conda-forge: onnxruntime, lwtnn, prmon, nlohmann_json.
   - The conda-forge versions of acts, vecgeom and geomodel **do not match** ATLAS's versions, so pinning to conda-forge versions means patching Athena.
   - For frontier_client, CORAL and COOL, use the Spack recipes as references.
5. **C++ standard:** Athena ≥ 25.0.70 uses `std::print`, so C++23 is needed; AtlasCMake enables C++23 for gcc ≥ 15 or clang ≥ 22. Use the conda-forge ROOT `cxx23` variant and a compiler ≥ gcc 15 / clang 22, or force `-DCMAKE_CXX_STANDARD=23`. Verify the ROOT dictionary standard matches, because ROOT's `root_cxx_standard` run-export enforces it.
6. **Build-system gotchas already found by others:**
   - `CMAKE_INSTALL_LIBDIR` absolute;
   - `CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY`;
   - CMP0167 FindBoost;
   - ROOT component names (`Cint`, `Math`, `pthread`, `PyROOT`);
   - `ROOT_*_EXECUTABLE` variables;
   - `lcg_generate_env`;
   - locale (`C.UTF-8`);
   - `PIP_ROOT`;
   - non-parallel-safe `copy_directory` in the externals superbuild;
   - Python as a runtime dependency;
   - platform-string mismatch;
   - glibc-2.17 sysroot vs `_dlfcn_hook`;
   - libxml2 ≥ 2.12 API;
   - `-Wl,--no-undefined` / `-z defs` on macOS.
7. **Runtime relocatability** is the recurring theme across Gaudi, DD4hep and LHCb. Plan activation scripts or patches for plugin, component and confdb discovery without `LD_LIBRARY_PATH`. Remember that ROOT `.pcm` files must not be prefix-rewritten (see the fwlite `ignore_prefix_files` lesson in the CMSSW notes).
8. **Keep TDAQ-dependent packages out of scope initially.** Athena and DetCommon use tdaq/tdaq-common, AnalysisBase does not, and atlas.bits likewise chose a *"tdaq-free"* subset.
9. **Talk to people early:** cburr (POC owner, conda-forge core), matthewfeickert and kratsg (ATLAS reviewers), clemenci (Gaudi), akraszna (AtlasCMake and macOS), Buncic (bits, to avoid duplication). The HEP Packaging Coordination channel is the natural venue.
10. **Pitch:** a native osx-arm64 and aarch64 AnalysisBase for Open Data and analysis-facility users, where today the only option is an amd64-only 1.1 GB container. Belle II and LHCb have already moved in this direction.

---

## 8. Not found or not checked

- ATLAS JIRA (ATLINFR, ATEAM) and ATLAS-internal Indico or TWiki pages about conda, spack or "LCG-less" builds: not publicly accessible. Indico search needs login, and GitLab blob search needs auth. Nothing public found.
- Any macOS **arm64** AnalysisBase build, or any macOS Athena build: none found.
- The content of the ATLAS patches in `atlas/Gaudi` v40r4.00x relative to upstream: not diffed.
- A per-file license exception list for athena: not produced.
- The ATLAS ARM CHEP paper's full text: read only through search summaries.
