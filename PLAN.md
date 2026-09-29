# Plan: packaging Athena for conda-forge

Goal: install Athena (the ATLAS offline software) with `conda install`/`pixi add` on
**linux-64, linux-aarch64 and osx-arm64**, without CVMFS or an ATLAS environment. It must be
split into packages that each build within conda-forge CI limits.

This document is the result of an initial exploration (2026-09-29). Details and evidence:

- `athena-notes/research/build_system.md`: AtlasCMake, the project model, how a project is built
  on an installed base, the install area, how externals are found, the runtime environment, macOS.
- `athena-notes/research/deps_conda_forge.md`: every external checked against conda-forge
  repodata (version, platforms, ATLAS patches, action).
- `athena-notes/research/package_graph.md`: size, dependency graph, the ATLAS projects as
  boundaries, and a first layer proposal. Scripts in `athena-notes/analysis/scripts/`.
- `athena-notes/research/prior_art.md`: earlier attempts (Chris Burr's conda POC, EP-SFT's
  `atlas.bits`, AnalysisBase on macOS, the conda-forge Gaudi feedstock, the LHCb pixi stack).
- `athena-notes/research/runtime_data_platforms.md`: runtime data, conditions, hard-coded
  CVMFS paths, aarch64 and macOS portability, CUDA.

Reference release: **Athena 25.0.73** (tag `release/25.0.73`, commit `8c1c4b757d2`, built from
`nightly/main/2026-09-23T2100`), on CVMFS at
`/cvmfs/atlas.cern.ch/repo/sw/software/25.0/Athena/25.0.73/InstallArea/{x86_64,aarch64}-el9-gcc15-opt`.
It is built with gcc 15.2, cmake 4.4, C++23, on LCG_110_ATLAS_5 and AthenaExternals 25.0.73
(atlasexternals tag 2.1.91). The install area ships the complete `src/` tree, so no clone of
athena is needed for analysis. Small repos (atlasexternals, the ATLAS Gaudi and CLHEP forks)
are cloned into the git-ignored `_work/`.

---

## 1. What we are dealing with

### 1.1 Athena itself

| Quantity | Value |
|---|---|
| Packages | 1,966 in 29 top-level directories; 1,731 compile code, 130 python/scripts only |
| Targets | 1,168 libraries, 1,000 Gaudi components (+164 POOL/T-P/serialisation converter libs), 460 reflex dictionaries, 191 executables, 1,892 tests (1,111 compiled) |
| Translation units | 14,861 real + 599 generated = **15,460** without tests; 16,735 with |
| Installed | `lib/` 3.1 GB (aarch64), `src/` 329 MB (it *is* the header set), `data/` 338 MB |
| Estimated CPU cost | 34 CPU-h at 8 CPU-s/TU, 64 CPU-h at 15 CPU-s/TU (unmeasured; CMSSW measured 7.6, Athena is likely heavier: 42 % of TUs reach Eigen) |

**Dependency structure** (`package_graph.md` §2):
- The library link graph is effectively a DAG (2 cycles, both through INTERFACE libraries).
- At the subsystem level 24 of 29 top-level directories form one strongly connected component,
  so, as for CMSSW, **the split must be per package**, driven by dependency closure.
- **Unlike CMSSW, there are essentially no undeclared cross-package includes** (11 found, all
  `#ifdef`-guarded). Per-target include paths make the CMake link graph sufficient for closure.
- Python imports form one big cycle, but the configuration flags check `moduleExists()` before
  loading a subsystem, so a partial installation is tolerated by design.

**The ATLAS projects are not layers.** AnalysisBase, AthAnalysis, AthSimulation and
AthGeneration build overlapping package sets with different preprocessor flags
(`XAOD_STANDALONE`, `XAOD_ANALYSIS`, `SIMULATIONBASE`, `GENERATIONBASE`). Their package sets
are not closed in Athena mode (an Athena-mode AthAnalysis needs 137 more packages). They are
all cut from `main`: 25.0.x (Athena, AthSimulation, DetCommon) and 25.2.x (AnalysisBase,
AthAnalysis) come from the same branch, and the filters at the 25.0.73 commit reproduce the
25.2.112 package lists exactly.

### 1.2 Externals

Athena's externals come from four places (`deps_conda_forge.md` §1):
1. **AthenaExternals** (atlasexternals 2.1.91) builds 31 packages: Gaudi (ATLAS fork v40r4.002),
   ACTS 47.7.0, GeoModel 6.29.0, Geant4 (ATLAS fork 10.6.3), CLHEP (ATLAS fork 2.4.7.1_atl01),
   VecGeom, vecmem, onnxruntime, lwtnn, Coin3D/SoQt, yampl, boost-mpi3, APTypes, ...
2. **LCG_110_ATLAS_5**: ROOT 6.40.02 (C++23), Boost 1.91, TBB, Python 3.13, Eigen, XRootD,
   generators, ~150 Python packages.
3. **tdaq-common 14-00-00**: ers, eformat, EventStorage, dqm_core, ...; it also carries
   CORAL/COOL 3_3_20, CrestApi 6.2.12 and chai 2.1.0.
4. **tdaq** (full online software): used by one package (`ByteStreamEmonSvc`) and some
   online-only scripts. **Dropped.**

Summary:
- **Available and fine** (about 38 of the ~50 core externals): ROOT 6.40.02 cxx23 (exact match,
  all three platforms), Boost, TBB, Python 3.13, Eigen 3.4, HepMC3, HepPDT, XercesC, XRootD,
  Davix, HDF5, HighFive, fmt, nlohmann_json, onnxruntime-cpp, lwtnn, FastJet(+contrib),
  protobuf/grpc, Qt5/Coin3D/SoQt (VP1), openmpi, LHAPDF, Rivet, YODA, and all runtime Python
  modules except `histgrinder`.
- **Missing, new recipes needed:** CORAL and COOL (without Oracle and CORAL_SERVER),
  frontier-client (**reuse the CMSSW repo's recipe: same version 2.10.2**), CrestApi, chai,
  tdaq-common (subset), vecmem, yampl, boost-mpi3, APTypes, histgrinder.
- **Present but not usable as is:**
  - **Gaudi:** ATLAS's fork is upstream v40r4 + 2 commits (drop ROOT's SSL API). conda-forge
    has 40.4 and 40.6, **Linux only** (the feedstock skips macOS). Upstream Gaudi has had macOS
    and libc++ support since v40r3 and conda plugin-path discovery since v40r4, so the gap is
    in the feedstock, not upstream.
  - **ACTS:** conda-forge `acts-core` 45.5.1, core only; Athena needs 47.7.0 with the Json,
    GeoModel, Root and Fatras plugins. ACTS breaks its API every major, so this is a hard pin.
  - **GeoModel:** 6.29.0 exists but only for linux-64.
  - **CLHEP:** Athena needs the ATLAS fork's `RandBinomial` private→protected change and
    Ziggurat without `thread_local`.
  - **Geant4:** ATLAS runs its own static 10.6.3 fork; conda-forge has 11.4.2. Athena includes
    `G4AtlasRK4.hh`, which exists only in the fork. Simulation only (79 packages).
- **Licence problems:** CORAL, COOL, CrestApi and yampl have **no licence files**. This is the
  same blocker CMSSW has with CORAL.
- **GPU:** the reference build has CUDA. A CPU-only build turns off ACTS traccc/GNN and filters
  out `ActsGPU*`, `AthTriton*`, `TracccTritonClient`, `EFTracking*` (unguarded `find_package`s).
  `vecmem` is still needed (`AthDevice*`).

### 1.3 The build system (AtlasCMake)

(`build_system.md`.)
- Plain CMake with the AtlasCMake module set (atlasexternals `Build/AtlasCMake` + `Build/AtlasLCG`).
  Each installed project carries a copy in `cmake/modules/`.
- **Projects stack natively.** A project does `find_package(<Base>)` and
  `atlas_project(USE <Base> <version>)`; the base's config recursively finds *its* bases and
  copies their imported targets, and a local target shadows the base's. WorkDir → Athena →
  AthenaExternals (three levels) is used every day. Deeper chains are supported by design but
  untested. **This is much closer to what we need than SCRAM was**: each layer can be its own
  ATLAS project with a package filter file, built on the previous one.
- `find_package(LCG 0)` is a supported "no LCG release" mode (AnalysisBaseExternals uses it),
  so the externals can come from `CMAKE_PREFIX_PATH=$PREFIX`. It needs a one-line fix for
  `EXACT` with version 0.
- **The build runs what it builds:** `listcomponents`, `genconf` (instantiates every
  component), `genCLIDDB`, `genreflex` for ~535 dictionaries, `han-config-gen`, the L1Topo
  generators, python syntax checks and flake8. **Native builds on all three platforms.**
- **No RPATHs anywhere** (`CMAKE_SKIP_RPATH ON`): everything relies on `LD_LIBRARY_PATH`.
  That does not work on macOS (SIP) and is disliked on conda-forge, so AtlasCMake needs an
  option for RPATHs.
- The install area is relocatable (relative config paths, `${LCG_RELEASE_BASE}` for
  externals), except that AthenaExternals paths assume the CVMFS sibling layout
  `<root>/<Project>/<version>/InstallArea/<platform>`.
- Per-project merged files: `lib/<Project>.components`, `.confdb`, `.confdb2`, `.rootmap` and
  `share/clid.db`. Components and new-style configs are found through `GAUDI_PLUGIN_PATH`; the
  legacy `ConfigurableDb.py` only scans `LD_LIBRARY_PATH` and needs a patch.

### 1.4 Platforms

- **linux-aarch64 is low risk.** ATLAS has published aarch64 Athena releases since 23.0.0 and
  the platform is physics-validated; every 25.0 release since 25.0.37 has the full package set
  on aarch64, and atlasexternals CI builds all externals projects on `aarch64-el9-gcc15`.
- **CPU flags:** production is plain `-march=x86-64 -O2` (generic on aarch64), so conda-forge's
  defaults are fine. **CUDA:** all GPU packages skip themselves without nvcc, and the CPU
  simulation libraries do not link libcudart; build without CUDA.
- **linux-64** matches ATLAS's production platform; conda-forge's gcc 15 matches exactly.
- **osx-arm64 is the real unknown.** Full Athena has never been built on macOS. AnalysisBase
  built natively on Intel macOS from about 2016 to 2023, the Apple code paths are still in
  `Control/` (22 guarded files), and there is a clang 22 Linux nightly, but with libstdc++.
  Known blockers: Gaudi on conda-forge (above), GNU-ld flags that AtlasCMake applies to every
  clang, no RPATHs, Linux-only monitoring code, and libc++ strictness (only 4 files use
  libstdc++-only headers, but that says little) (the CMSSW experience: most macOS patches were code
  that libstdc++ let through). conda-forge's clang 21 is below ATLAS's C++23 threshold
  (clang ≥ 22), so C++23 has to be forced to match ROOT's cxx23 build.

### 1.5 Prior art worth reusing

(`prior_art.md`.)
- **Chris Burr's conda POC** (`gitlab.cern.ch/cburr/atlas-conda` and
  `cburr/atlascmake-conda-package`, Feb 2026, dormant): builds AnalysisBase and
  ColumnarAnalysis on linux-64 with the native `atlas_project()` build against conda-forge. It
  packages AtlasCMake as a noarch conda package with 5 small patches, 12 Find modules (the key
  one rewrites ROOT component names) and stub `*ExternalsConfig.cmake` files that replace the
  externals projects. Athena needed 2 source patches. **This is our starting template.**
- **EP-SFT's `bitsorg/atlas.bits`** (Sep 2026, active): runs ATLAS's own build scripts on a
  bits-built LCG. Got to AthenaExternals and a 12-package HelloWorld subset of 25.0.70. Its
  commit log lists pitfalls that apply to us (CORAL/COOL not in LCG any more, Oracle and
  CORAL_SERVER stripped, chai arrived after 25.0.70, C++23 for `std::print`, a non-parallel-safe
  externals superbuild, locale, `PIP_ROOT`, Python as a run dependency).
- **conda-forge `gaudi`** (chrisburr) and **`clemenci/pixi-stack`** (Gaudi + LHCb as rattler-build
  packages): the Gaudi side of this is being solved by others.
- **cmssw-in-conda-forge**: frontier-client recipe, the local Docker/macOS build loop, the
  activation-script and RPATH lessons, the per-layer closure tooling, and conda-forge's ROOT
  6.36 macOS module problem (not an issue here: we need 6.40 anyway).
- No Spack, Nix, Homebrew or conda package of Athena exists. The names `athena`,
  `analysisbase`, `atlascmake` are free on conda-forge.
- **Demand:** ATLAS Open Data tells users to run an amd64-only AnalysisBase container; there is
  no native arm64 or macOS option.
- **People:** chrisburr (POC, gaudi feedstock, conda-forge core), clemenci (Gaudi), akraszna
  (AtlasCMake, the old macOS work), matthewfeickert and kratsg (ATLAS feedstock maintainers),
  paulgessinger (acts feedstock), Buncic (atlas.bits).

### 1.6 Runtime data

(`runtime_data_platforms.md`.)
- **Conditions metadata and geometry go over the network.** COOL conditions and the geometry
  database are read through Frontier by default. Anonymous queries to
  `atlasfrontier-ai.cern.ch:8000/atlr` (directly and through ALRB's proxy `v4f.hl-lhc.net:6082`)
  returned rows; **not yet retested from outside CERN's network**. CREST (`crest.cern.ch`) is
  publicly readable too, but is only the default for Run 4. DBRelease is legacy.
- **The gap is the POOL conditions payload files**: ROOT files that COOL entries point to. They
  live only on `/cvmfs/atlas-condb.cern.ch` (839 GB; MC payloads about 3.8 GB, data about
  800 GB), their file catalogue hard-codes `/cvmfs` paths, and no HTTP mirror was found. This
  blocks reconstruction from RDO without CVMFS.
- **GroupData** (calibration files, 1.15 TB) cannot be packaged, but PathResolver can download
  from `https://atlas-groupdata.web.cern.ch` with `PATHRESOLVER_ALLOWHTTPDOWNLOAD=1`. It never
  checks the HTTP status, so a 404 page is cached as the file: needs an (upstreamable) patch.
  About 13 configs hard-code `/cvmfs/.../GroupData` paths.
- **ReleaseData** (field maps etc.) is small enough to package: a v20 subset of about 0.35 GB,
  plus TwissFiles.
- `authentication.xml` on CVMFS holds 62 Oracle passwords: **never ship it**; ship an empty one.
- Geant4 10.6.3 data sets are 1.86 GB (simulation only).
- **Consequence:** AnalysisBase/AthAnalysis-style jobs on DAOD_PHYSLITE need network access
  only. ATLAS Open Data PHYSLITE (CC0) is readable over HTTPS, which gives tests and demos a
  CVMFS-free input. Full reconstruction needs CVMFS for POOL payloads until that is solved.

---

## 2. Key decisions

### D1. Build system: native AtlasCMake against conda-forge externals

| | (A) AtlasCMake + conda shim (cburr) | (B) Keep LCG semantics, generate an LCG view (atlas.bits) |
|---|---|---|
| Athena build | unchanged `atlas_project()` | unchanged `build.sh` |
| Externals | conda-forge packages, found via a thin set of Find modules and stub externals configs | a fake `LCG_externals_<platform>.txt` pointing into the prefix |
| AthenaExternals | replaced by recipes (ours or feedstocks) | built as one big superbuild |
| conda-forge fit | idiomatic | a superbuild inside one recipe; not acceptable for conda-forge |

**Recommendation: (A).** It is proven for AnalysisBase and keeps Athena's own CMake intact.
The shim is a noarch `atlascmake` package (AtlasCMake + AtlasLCG from atlasexternals 2.1.91,
cburr's patches, the `EXACT` fix, an RPATH option, Apple linker-flag guards, Find modules,
stub `AthenaExternalsConfig.cmake`). Offer the patches upstream to atlasexternals.

### D2. How to split

- **Each layer is its own ATLAS project**: our own `CMakeLists.txt` derived from
  `Projects/Athena` (settings, Pre/PostConfig) and `Projects/WorkDir` (source-or-installed
  helpers), `atlas_project(<Layer> USE <PreviousLayer> 25.0.73)`, and a package filter file
  generated by `layers.py`. **The top layer is named `Athena`**, so that `find_package(Athena)`
  and a user's `cmake athena/Projects/WorkDir` behave as on CVMFS.
- **Layers are separate recipes/feedstocks**, pinned `==` to each other, as for CMSSW.
- **Install layout, to be decided by the M1 spike:**
  - **(A) one install area per layer** in the CVMFS shape
    (`$PREFIX/<root>/<Layer>/25.0.73/InstallArea/<platform>/`): no file clashes and no
    ownership patches, ATLAS's own `setup.sh` chaining keeps working, but every search path
    has N entries (one activation script per layer).
  - **(B) one shared area** (the CMSSW model): simpler environment, but `clid.db`,
    Pre/PostConfig and the top-level files clash and need patches and a careful installer.
  - **Recommendation: try (A) first**; it is how ATLAS itself stacks projects.
- **First layer proposal** (`package_graph.md` §4, all closed, 0 dependencies on later layers):

| # | Layer | Build TUs | Delivers | New heavy externals |
|---|---|---|---|---|
| 1 | core | 1.2k | `athena.py`, StoreGate, ComponentAccumulator, POOL/RNTuple I/O, IOVDb/CREST, ByteStream | Gaudi, CORAL/COOL, CrestApi/chai, tdaq-common, HepMC3 |
| 2 | detdescr | 1.6k | Identifiers, GeoModel geometry, ACTS tracking geometry, magnetic field | GeoModel, ACTS |
| 3 | edm | 1.8k | xAOD and trigger EDM: read/write AOD/DAOD | |
| 4 | edm-det | 1.5k | RDO/ESD/HITS I/O | FastJet |
| 5 | analysis | 1.7k | CP tools on DAOD_PHYS/PHYSLITE | onnxruntime, lwtnn, HDF5, LHAPDF, Triton client |
| 6 | sim | 1.4k | `Sim_tf.py` | Geant4, Pythia8 |
| 7 | reco-tracking | 1.2k | ID/ITk tracking, vertexing | (Eigen-heavy) |
| 8 | reco | 2.2k | `Digi_tf.py`, `Reco_tf.py` without trigger | |
| 9 | trigger | 1.6k | L1/HLT | |
| 10 | rest | 1.3k | derivations, DQ, VP1 | Qt5/Coin3D |

  The worst case is reco at about 4.5 h wall on 2 cores at 15 CPU-s/TU, before tests. In
  practice the layers form a chain (sim is needed by reco-tracking and reco through shared
  monitoring and interface packages); moving those down might let sim become a leaf. If the
  measured cost allows, or conda-forge grants larger runners, merge neighbouring layers: fewer
  feedstocks matter a lot for maintenance.

### D3. Products: full Athena, AnalysisBase, or both

The ATLAS "light" projects are different binaries under the same library names, so an
`analysisbase` package and the Athena layers cannot be installed in the same environment
(unless they live in separate install areas and never share an activation).
- **Athena layers** are the goal of this repo.
- **AnalysisBase** (~2.1k TUs, one job, no Gaudi/CORAL/tdaq, proven by cburr's POC) is the
  cheapest deliverable and the one with the clearest external demand (Open Data, analysis
  facilities, osx-arm64).
- **Recommendation:** Athena first, as intended. Keep AnalysisBase in mind as a follow-up that
  reuses the same `atlascmake` shim, and as a lower-risk vehicle for the macOS port (it avoids
  Gaudi). Needs a decision from us.

### D4. Versions and pinning

- One release: **25.0.73**, packages versioned `25.0.73`, layers pinned exactly to each other.
- ROOT **6.40.02, `root_cxx_standard` 23** (a first-class conda-forge variant on all three
  platforms; exact match with ATLAS). Python 3.13, Boost 1.90 (what conda-forge's gaudi/geant4
  are built against), TBB 2023 (same ABI as ATLAS's 2022.2), Eigen 3.4.0, HighFive 2.10.1,
  onnxruntime-cpp 1.26, HepMC3 3.3, patched CLHEP 2.4.7.1, ACTS 47.7.0, GeoModel 6.29.0.
- **Gaudi:** conda-forge's 40.4 builds exist for ROOT 6.40.2/cxx23 only with clhep 2.4.7.2,
  and for 6.40.4 with 2.4.7.1. Since we need a patched CLHEP and osx-arm64 anyway, we will most
  likely build Gaudi ourselves (ATLAS fork v40r4.002). The conda-forge way is to contribute
  osx-arm64 to the gaudi feedstock rather than fork it; decide in M2.
- conda-forge migrations (ROOT, boost, tbb, python) force rebuilding every layer in order;
  the same open problem as CMSSW.

### D5. Simulation and Geant4

Deferred until the reco layers work. Options: conda-forge Geant4 11.4 plus an Athena patch for
`G4AtlasRK4` (results then differ from production), the ATLAS fork's 11.2.2.3 tag, or the
production 10.6.3 fork. Only the `sim` layer is affected.

### D6. Runtime data and conditions

- The activation scripts replace `setup.sh`/`env_setup.sh`. Beyond the search paths
  (`PATH`, `PYTHONPATH`, `GAUDI_PLUGIN_PATH`, `ROOT_LIBRARY_PATH`, `ROOT_INCLUDE_PATH`,
  `JOBOPTSEARCHPATH`, `DATAPATH`, `XMLPATH`) they set:
  - `CALIBPATH`: a user cache, then `/cvmfs/.../GroupData` if mounted, then the HTTP mirror;
    `PATHRESOLVER_ALLOWHTTPDOWNLOAD=1`;
  - `FRONTIER_SERVER` (if unset) to ATLAS's public Frontier servers, `CORAL_DBLOOKUP_PATH`, and
    `CORAL_AUTH_PATH` to an empty `authentication.xml`. **Ask ATLAS DB/ADC before publishing a
    default that sends anonymous users to their Frontier servers** (CMS's are used this way);
  - `ATLAS_POOLCOND_PATH` when CVMFS is present.
  Like the CMSSW site configuration, **CVMFS is optional**: used when mounted, never required
  for what works without it.
- Package ReleaseData (subset) and TwissFiles as noarch data packages. Do not package GroupData,
  data POOL payloads or `data-art`.
- **Open:** POOL conditions payloads for reconstruction without CVMFS: an HTTP mirror (ask ATLAS)
  or an MC-payload data package (~3.8 GB, too big for one conda package; catalogue rewrite
  needed). Until then, `Reco_tf.py` tests require CVMFS.

---

## 3. Milestones

### M0: tooling and a local build loop (small)
- Docker containers for linux-aarch64 (native) and linux-64 (the CI image under Rosetta), as for
  CMSSW; a native macOS env under `_work/`. A `build-local.sh` adapted from the CMSSW one.
- `CLAUDE.md` for this repo.

### M1: `atlascmake` and the stacking spike (linux-aarch64)
- Package `atlascmake` (D1) starting from cburr's recipe, rebased on atlasexternals 2.1.91.
- Spike outside rattler-build: three chained ATLAS projects in one conda env with a HelloWorld
  closure (as atlas.bits did), then the same through rattler-build. Answers: does deep chaining
  configure and build, install layout (A) vs (B), RPATHs, `GAUDI_PLUGIN_PATH`/confdb discovery
  across projects, `clid.db` merging.
- **Measure CPU-s/TU and peak RAM per compile** on a sample of core and reco-tracking, to fix
  the layer sizes and the `-j` a 7 GB runner can afford.

### M2: missing externals
- Gaudi (decision in D4), patched CLHEP, CORAL + COOL (no Oracle, no CORAL_SERVER),
  frontier-client (from the CMSSW repo), CrestApi, chai, tdaq-common subset, vecmem, yampl,
  boost-mpi3, APTypes, histgrinder, ACTS 47.7.0 with plugins, GeoModel 6.29.0 on all platforms.
- Start the licence conversations for CORAL, COOL, CrestApi and yampl early: they block
  submission, not building.

### M3: `athena-core` (linux)
`athena.py` runs a HelloWorld job, writes and reads a POOL file, and reads conditions from a
sqlite file.

### M4: detdescr, edm, edm-det
Build the ATLAS geometry, read AOD/DAOD in Athena and PyROOT.

### M5: analysis
CP tools on DAOD_PHYSLITE (e.g. ATLAS Open Data).

### M6: reco-tracking, reco, trigger
`Reco_tf.py` on a small RDO, with conditions (network or sqlite, D6).

### M7: sim (D5), rest, the `athena` metapackage and the developer workflow
A user's `Projects/WorkDir` build on top of the conda release, like `cmssw-devel`.

### M8: osx-arm64, in parallel from M3 onward
Gaudi on osx-arm64, AtlasCMake Apple fixes, RPATHs, libc++ fixes in Athena.

### M9: upstreaming and hand-off
AtlasCMake patches to atlasexternals, Athena patches to athena, coordination with cburr,
akraszna, clemenci and Buncic.

---

## 4. Risks

1. **Licences** of CORAL, COOL, CrestApi and yampl: without them nothing that reads conditions
   can go to conda-forge (CORAL is in `PersistentDataModel`, i.e. the core layer). Also: a
   per-file licence scan of athena ("Apache-2.0 except where other licenses apply").
2. **POOL conditions payloads** exist only on CVMFS: reconstruction without CVMFS needs ATLAS's
   help (D6).
3. **osx-arm64**: depends on Gaudi on macOS (upstream-supported, untested on conda-forge) and an
   unknown amount of libc++ work in 15k TUs that have never seen macOS.
4. **Build cost and memory**: unmeasured; Eigen/ACTS-heavy layers and large reflex dictionaries
   may force `-j2` on 7 GB runners.
5. **Deep project chaining** is untested beyond three levels; configure time with thousands of
   copied imported targets per level.
6. **tdaq-common**'s build system is LCG-centric and has never been built outside EL9/gcc. It is
   needed from the core layer (ByteStream) unless ByteStream moves up.
7. **ACTS and GeoModel pins** tie our recipes to atlasexternals' versions; the conda-forge
   feedstocks move on their own schedule.
8. **Tests**: ATLAS tests are often full athena jobs needing data; running them in CI may cost
   more than building.
9. **Geant4 version** for simulation (D5).

---

## 5. Decisions taken (2026-09-29)

- **D1:** native AtlasCMake against conda-forge externals, through an `atlascmake` shim package
  built from Chris Burr's POC. (It became `athena-externals`, the AthenaExternals project
  itself: see the progress log.)
- **D2:** each layer is its own ATLAS project, built on the previous one; the top layer is
  named `Athena`. The install layout, (A) or (B), is decided by the M1 spike, trying (A) first.
- **D3:** full Athena is the main line. AnalysisBase is a later, separate product, and possibly
  the first vehicle for osx-arm64 since it needs no Gaudi.
- **D4:** build Gaudi ourselves (ATLAS fork v40r4.002) to start, since a patched CLHEP and
  osx-arm64 are needed anyway. Revisit contributing to the conda-forge gaudi feedstock later.
  **Confirmed by the M1 spike:** Gaudi must be built with the same GCC major as Athena
  (`std::format` ABI), and conda-forge's 40.4 is a gcc 14 build.
- **D2 install layout:** (A), one install area per layer under
  `$PREFIX/opt/athena/<Project>/<version>/InstallArea/<platform>` (M1 spike).
- **Linux sysroot:** `c_stdlib_version` 2.34 (M1 spike).
- Contact cburr, clemenci, akraszna and Buncic early (done by the user, not from this repo);
  the licence and POOL-payload questions need ATLAS.
- Next: M0 and M1 (the stacking spike and cost measurement on linux-aarch64).

---

## 6. Progress log

### 2026-09-29: initial exploration

Five research reports (listed at the top) on the build system, the externals, the package
graph, prior art, and runtime data and platforms. ATLAS CVMFS (`atlas.cern.ch`,
`atlas-condb.cern.ch`, `atlas-nightlies.cern.ch`, `sft.cern.ch`) is mounted on this machine.

### 2026-09-29: the M1 spike: Athena projects stack in a conda prefix

Scripts in `athena-notes/spike/` (see its README), run natively on linux-aarch64 in the
`athena-dev` container, outside rattler-build but with the same host/build prefix split.

**Stacking works.** atlasexternals' own `AthenaExternals` project, configured with LCG 0 and
no bundled externals, gives the base that Athena's project files expect. On it, three Athena
layers, each its own ATLAS project built only against the installed ones below it, the top one
named `Athena`: four levels, one more than ATLAS itself uses. Everything is installed under
`$PREFIX/opt/athena/<Project>/25.0.73/InstallArea/<platform>` (install layout (A) of D2), and
in that shape ATLAS's own `setup.sh` of the top layer sets up the whole chain (PATH, libraries,
python, job options, data, CMake prefixes). The 17-package link closure of `AthExHelloWorld`
plus the 32 packages `athena.py` needs to start builds that way, including AthenaServices,
AthenaMP, PerfMon and genconf/CLID DB/dictionary generation in every layer.

**What it took:**
- AtlasCMake: cburr's 5 patches apply unchanged to atlasexternals 2.1.91.
- AtlasLCG: `find_package(LCG 0 EXACT)` has to succeed (patch 0001), and `lcg_generate_env`
  must tolerate a Gaudi found through its own CMake configuration (0002). Both upstreamable.
- Find modules: AtlasLCG's `FindTBB` clashes with TBB's own CMake configuration (conda-forge's
  TBB also exports `tbbbind`), so the shim has its own. ATLAS's `FindGaudi.cmake` wrapper (it
  creates the plain `GaudiKernel` target) and the `External/*/cmake/Find*.cmake` modules are
  only installed by AthenaExternals when it builds those externals, so the shim installs them.
- `link_libraries(Threads::Threads)` in the externals' PostConfig (cburr needed it too).
- **The Linux recipes need `c_stdlib_version` 2.34** (EL9's glibc, what ATLAS targets):
  PerfMonComps uses `mallinfo2` (glibc 2.33), and 2.17 is behind cburr's `_dlfcn_hook` patch.
  `root_base` pins its *host* prefix to the 2.17 sysroot, but the compiler lives in the build
  prefix, so this works in rattler-build.
- The compilers must be given by absolute path: an installed layer's `setup.sh` puts the host
  prefix's `bin/` first, where `root_base`'s own compiler (with the 2.17 sysroot) lives. Same
  for Python (`-DPython_EXECUTABLE`).
- `-DCMAKE_INSTALL_SO_NO_EXE=0`: on a Debian-like build host CMake installs libraries without
  the execute bit, and `athena_preload.sh` finds `libexcabort.so` with `which`.
- Layer projects must live in `athena/Projects/<name>/`: PyUtils finds the source tree as
  `${CMAKE_SOURCE_DIR}/../../`.
- Build-time tool dependencies the link graph does not show: every component needs
  `Control/CLIDComps` (genCLIDDB) in the same or a lower layer, and PyUtils needs
  `pygraphviz` in the build environment. `layers.py` has to learn about the first.

**Gaudi has to be built with Athena's compiler.** conda-forge's gaudi 40.4 is a gcc 14 build
and exports libstdc++'s `std::format` internals; Athena code built with gcc 15 binds to them
and `genconf` segfaults in `Gaudi::Utils::toStream(double)` for every component with a
`double` property. **The build does not fail**: the component is just missing from the
`.confdb2`, and the job fails much later (`GaudiConfig2.Configurables has no attribute
AthSequencer`). Recipe tests must check that every component made it into the databases.
ATLAS's fork v40r4.002 built with gcc 15 fixes it, which settles D4. (conda-forge's gaudi also
exports `GaudiKernel` with an absolute path to `librt.so` in its feedstock's build sysroot:
worth reporting to the feedstock.)

**New externals, all built in the spike:** CORAL 3_3_20 (upstream lcgcoral, with a patch
making MySQL/Oracle/Frontier/tests/server optional); boost-mpi3 v0.81 with ATLAS's patch
(needs openmpi); yampl 1.2 (a patch to use conda-forge's zeromq + cppzmq instead of its
bundled copy). AthenaServices also needs valgrind's headers (conda-forge has them on Linux
only). CORAL and yampl have no licence file.

**Cost.** ninja's timings at `-j8` on the lowest layers (light Control packages): about
**6 CPU-s per non-test translation unit** including dictionaries and generated code, 7–9 s
per dictionary; compiled tests roughly double the total. Heavier xAOD/Eigen code is still to
be measured, and so is memory.

**HelloWorld runs.** `athena.py AthExHelloWorld/HelloWorldConfig.py` processes its 10 events
and exits 0, and its output matches ATLAS's reference log for the test; with `--threads=2`
the AvalancheScheduler runs two events in flight. Getting there took:
- the whole conditions client stack, because `initConfigFlags()` imports `IOVDbSvc`: COOL
  3_3_20 (one patch: COOL's environment-file generator misparses its lists when a value is
  empty, which `man -w` and `$QT_PLUGIN_PATH` are in a minimal container), CrestApi 6.2.12 and
  chai 2.1.0 (with nanobind), unpatched. So even the smallest useful layer needs CORAL, COOL,
  CrestApi and chai;
- the python closure of the configuration code (Tools/PyUtils, PyJobTransforms, Campaigns,
  GeneratorConfig, GaudiSequencer, POOL's CollectionSvc/StorageSvc/PoolSvc, PathResolver),
  found with `pyclosure.py` plus trial and error for imports inside functions;
- `ROOT_pthread_LIBRARY=pthread` (as in cburr's shim): ~180 packages ask for a "pthread" ROOT
  component, and AtlasLCG's FindROOT otherwise finds root_base's glibc 2.17 `libpthread.so`,
  whose linker script does not resolve in the 2.34 build sysroot;
- keeping the host prefix's sysroot out of `CMAKE_PREFIX_PATH` (a spike artifact: rattler-build
  does not activate compilers in the host prefix).

Also found: `athena.py` is a `#!/bin/sh` script with bash arrays, which fails where `/bin/sh`
is dash (Debian/Ubuntu); an upstream fix is `#!/bin/bash`.

**The M1 stacking question is answered.** Open from M1: memory per compile job and the cost
of heavier code (needs a bigger layer), and running this through rattler-build.

**Next:** the first real recipes: the `atlascmake` shim (AtlasCMake + AtlasLCG with the
patches, our Find modules, the conda PostConfig, the AthenaExternals base project), Gaudi
(`atlas-gaudi`, ATLAS's fork), `lcg-coral`, `lcg-cool`, `crestapi`, `chai`, `yampl`,
`boost-mpi3`, then the first Athena layer through rattler-build.

### 2026-09-29: the first recipes; athena-core runs HelloWorld through rattler-build

`athena-notes/build-local.sh` (from the CMSSW one) builds `recipes/` in the container, in
dependency order: `boost-mpi3`, `yampl`, `frontier-client` (the CMSSW repo's recipe,
unchanged), `lcg-coral`, `lcg-cool`, `crestapi`, `chai`, `atlas-gaudi`, `athena-externals`,
`athena-core`. All build on linux-aarch64 and pass their tests: an MPI hello world, a yampl
ping-pong over ZeroMQ/pipes/shared memory, SQLite round trips through CORAL (python) and COOL
(PyCool), a CREST tag through JSON, a chai payload through its file-system plugin, a Gaudi job,
a trivial ATLAS project on top of `athena-externals`, and **`athena.py
AthExHelloWorld/HelloWorldConfig.py`, serial and with `--threads=2`, from the installed
`athena-core` package** (a fresh environment, set up by its activation script).

Decisions and findings:
- **The shim is `athena-externals` 25.0.73**, not `atlascmake`: it is AthenaExternals itself
  (AtlasCMake + AtlasLCG, cburr's patches as one patch file plus our two, ATLAS's
  `External/*/cmake` Find modules, our `FindTBB`/`FindCORAL`, the conda PostConfig), installed
  in the CVMFS layout, and the layers pin it `==` like each other. The platform name is set
  explicitly (`ATLAS_FORCE_PLATFORM`, `<arch>-cf-gcc<major>-opt`) so that recipes can compute it.
- One `variants.yaml` for everything that links the stack: ROOT 6.40.2 cxx23, Boost 1.90,
  CLHEP 2.4.7.1 (zipped with geant4 11.3.2 in the pinning; unpinned, Gaudi gets one build per
  CLHEP), `c_stdlib_version` 2.34 (13.3 on macOS).
- **The spike's Athena layer never found CORAL**: AtlasLCG's FindCORAL requires the CORAL
  server executables, which we do not build; CoraCool linked only because COOL shares the
  include directory. `athena-externals` has a FindCORAL without that requirement.
- CORAL and COOL are installed the conda way: python modules (and `liblcg_PyCoral`) in
  site-packages, no tests/examples/Oracle scripts. COOL's own FindCORAL is pointed at
  site-packages. `lcg-coral` conflicts with the CMS fork's `coral` (same library names), which
  is recorded as a `run_constraints`; one CORAL for both experiments is a later question.
- `atlas-gaudi` needs the gaudi feedstock's plugin-path patch: without it Gaudi finds no
  component factories unless `LD_LIBRARY_PATH`/`GAUDI_PLUGIN_PATH` is set (the recipe's test job
  runs without either). `-Drt_LIBRARY=rt` keeps the build sysroot out of the exported targets.
- chai is built without its python bindings (one Athena script uses them) so that it is not
  python-specific; its plugins are found next to `libchai`. CrestApi's public headers use
  Boost.Parameter, so it needs `libboost-devel` (its CMake configuration asks for Boost's).
- `check_confdb.py` (tests of `atlas-gaudi` and every layer) fails if a component has no
  configurable. The exceptions are rules (converters, `_PERS_`/`_TRANS_` aliases, ROOT storage
  technologies, one factory) with which every component of ATLAS's own 25.0.73 release on
  CVMFS has its configurable.
- `athena-core` is, for now, the spike's 54 packages. It builds from the release tarball as
  its own project (`Projects/CondaLayer`), sourcing the base's `setup.sh`, in 9 to 12 minutes
  at `-j10`. Its activation script sources the layer's `setup.sh` and saves/restores what it
  changes (provisional, D6). The InstallArea also carries the packages' sources (`src/`), as on
  CVMFS; to be weighed against package size.
- **GitLab's archive endpoint can return an empty 200 response for the athena tarball**
  (58 MB; it happened repeatedly for a while, from two machines). Locally the source cache was
  seeded by hand; in CI this would be a flaky download. A mirror (or `git` with a shallow
  clone) may be needed.

**Next:** grow `athena-core` to the full core layer (tdaq-common subset, HepMC3, XRootD/Davix,
the POOL/RNTuple I/O and ByteStream packages; `layers.py` must learn the CLIDComps build
dependency), measure memory per compile on it, and the M3 deliverables (write/read a POOL file,
conditions from SQLite).
