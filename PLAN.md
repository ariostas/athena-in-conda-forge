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
| 3 | edm | 1.7k | xAOD and trigger EDM: read/write AOD/DAOD | |
| 4 | edm-det | 1.3k | RDO/ESD/HITS I/O | FastJet |
| 5 | analysis | 1.6k | CP tools on DAOD_PHYS/PHYSLITE | onnxruntime, lwtnn, HDF5, LHAPDF, fjcontrib |
| 6 | reco-tracking | 1.3k | ID/ITk tracking, vertexing | (Eigen-heavy) |
| 7 | reco | 2.1k | `Digi_tf.py`, `Reco_tf.py` without trigger | |
| 8 | trigger | 1.5k | L1/HLT | |
| 9 | sim | 1.1k | `Sim_tf.py` | Geant4, Pythia8 |
| 10 | rest | 1.3k | derivations, DQ, VP1 | Qt5/Coin3D |

  The worst case is reco at about 4.5 h wall on 2 cores at 15 CPU-s/TU, before tests. The
  layers form a chain. sim was first placed before reco-tracking, which needed it only for
  its non-Geant4 part (monitoring, muon interfaces, fitter utilities); since M6 the
  reconstruction and trigger layers come first and take those packages themselves, and sim
  (Geant4) comes after them. If the
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

**Decided in M7: the production fork**, `atlas-geant4` (10.6.3.15 with atlasexternals' four
patches and VecGeom 1.1.21 with its three), static and multithreaded as AthenaExternals builds
it, so that the simulation can be checked against ATLAS's release like every other layer. It
conflicts with conda-forge's geant4 and vecgeom (`run_constraints`); the data sets are
conda-forge's `geant4-data-*` packages in the 10.6 versions. Moving to Geant4 11 is ATLAS's
decision, and would then be a version bump here.
The simulation then agrees with the release in its input and in the amounts of hits, but is not
bit-identical, for a reason not found yet (progress log, M7).

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

### M8: linux-64 and osx-arm64
Gaudi on osx-arm64, AtlasCMake Apple fixes, RPATHs, libc++ fixes in Athena; linux-64 with
references from ATLAS's x86_64 release.

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
6. ~~**tdaq-common**'s build system is LCG-centric and has never been built outside EL9/gcc.~~
   Retired: its packages build on a small shim of the tdaq CMake functions (progress log).
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

### 2026-09-29: the full core layer (M3)

`athena-core` is now the whole `core` layer of `layers.py` (177 packages) plus
GeneratorConfig and McEventSelector, which job configurations import. It builds with
`rattler-build` on linux-aarch64 and passes four tests:
- HelloWorld, serial and multi-threaded;
- **conditions from SQLite through POOL**: ATLAS's IOVDbTestAlg write and read jobs. The write
  job puts conditions payloads in a POOL file and registers them in a COOL SQLite database; the
  read job reads them back through IOVDbSvc. The output matches ATLAS's reference logs except
  for three framework debug lines;
- **raw data**: an EventStorage file of random events written with tdaq-common's eformat,
  then listed and copied with Athena's `AtlListBSEvents` and `AtlCopyBSEvent`;
- the component check: 486 components, and every one has its configurable or matches a
  documented exception.

New and changed recipes:
- **`tdaq-common` 14.0.0**:
  - the packages Athena uses outside the online and DQ code: ers, compression, eformat,
    EventStorage, CTPfragment, hltinterface, MuCalDecode and circ;
  - sources are the public `atlas-tdaq-software` repositories, at the submodule commits of
    `tdaq-common-cmake`'s `tdaq-common-14-00-00` branch. They are identical to CVMFS;
  - licence Apache-2.0 (one LICENSE file, identical in every package);
  - the packages' own CMakeLists.txt files, unmodified, build on a ~200-line shim of the
    `tdaq_*` functions (`cmake/TDAQShim.cmake`) instead of the LCG-centric cmake_tdaq;
  - conda layout: the Boost.Python modules (`libpyeformat`, `liberspy`, ...) go in
    site-packages, because python imports them by those names;
  - tests: events written with the python bindings, read back in python and in C++;
  - `athena-externals` ships a `Findtdaq-common.cmake` for this layout, without the TDAQ
    environment (`TDAQ_RELEASE_BASE`, `TDAQ_PYTHON_HOME`);
  - left out for now:
    - the ROOT-dependent packages (dqm_core, dqm_algorithm_helper, HistogramStyles, webdaq),
      needed by DQ and trigger;
    - df_ef_interface, which has no licence file.

  This retires risk 6: tdaq-common's build system was not an obstacle.
- **`athena-externals`** also builds dSFMT (`+ External/dSFMT`). It is a static library whose
  sources are in atlasexternals (BSD-3-Clause, licence added), used by
  AtlasCLHEP_RandomGenerators.
- **`athena-core`**:
  - adds tdaq-common, HepMC3, XRootD, Davix, libprotobuf, gperftools and a Fortran
    compiler (the layer project now enables Fortran, like `Projects/Athena`);
  - `ATLAS_ALWAYS_BUILD_TESTS=OFF`. Compiled unit tests are about a quarter of the build
    time, and four of them need later layers (xAODJet, xAODEgamma);
  - `ATLAS_EXTERNAL` points nowhere, and the build fails if an `authentication.xml` is ever
    installed. AtlasAuthentication installs one when it finds it on AFS.
- **`layers.py`** knows that every package with components needs `Control/CLIDComps` at build
  time (in `graph.py`). This changes no layer assignment today.

Two Athena patches, both small and upstreamable:
1. **CLHEP.** AtlasCLHEP_RandomGenerators derives from `CLHEP::RandBinomial`, whose members
   are private upstream and protected in ATLAS's CLHEP fork (`CLHEP_2_4_7_1_atl01`). The
   patch reads them as protected with a scoped `#define`, which is ABI-neutral. The fork's
   other change, to RandGaussZiggurat and RandExpZiggurat (no `thread_local`, a rounding fix),
   changes random sequences. That matters for simulation and digitization reproducibility, not
   for core: raise it with the clhep feedstock and ATLAS before the sim layer (D5).
2. **GeoModel flags.** `GeoModelConfigFlags` imports `DumpGeo` (DetectorDescription), and
   every IOVDb job reads a GeoModel flag (`IOVDb.UseCREST` depends on `GeoModel.Run`). The
   patch guards the import with `moduleExists`, as AllConfigFlags does for other optional
   categories. Also, `GeoModel.Run` is deduced from the geometry tag through AtlasGeoModel and
   the geometry database, so **core-only conditions jobs must set `GeoModel.Run`** (or
   `IOVDb.UseCREST`) explicitly. The link graph shows neither dependency; python imports
   inside flag generators are the next thing to scan for when drawing layer boundaries.

**Cost** (`compile_cost.py`: the ninja log, plus 164 compiles re-run for peak memory):
- the layer builds in **12 to 15 minutes at `-j10`** on the Mac's linux-aarch64 VM without the
  unit tests (the whole recipe, tests included, in 13 minutes; the package is 34 MB): about 8 CPU-s per translation unit, dictionaries and genconf included. That is
  roughly 1.5–2.5 h on a 2-core conda-forge runner;
- peak RSS per compile: median 350 MB, p90 0.7 GB, max 2.2 GB (the xAODTrigger reflex
  dictionary, whose genreflex step alone takes 6 minutes). **`-j4` fits in 7 GB**; heavier
  (Eigen) layers still need measuring the same way.

Also: the `authentication.xml` guard; `KEEP_BUILD=1` in `build-local.sh`; tdaq-common in the
default build order.

**Next:**
- M4: externals for `detdescr` (GeoModel 6.29.0, ACTS 47.7.0, vecmem), then the layer itself;
- scan python imports in flag and config generators for layer-crossing dependencies;
- the runtime python dependencies of core (psutil, matplotlib, pandas, sqlalchemy for
  PerfMon's scripts; boto3 and stomp.py for EventIndex), deciding which become run
  requirements.

### 2026-09-30: the detdescr layer (M4, first part)

New externals:
- **`geomodel` 6.29.0** (outputs `geomodel-core` and `geomodel-tools`), built as ATLAS builds it
  (`GEOMODEL_BUILD_TOOLS` only). conda-forge's geomodel feedstock has the same split but builds
  linux-64 only, and all its outputs depend on Geant4, Qt6, Coin3D, SoQt6 and HDF5 because they
  share one staging build with the visualization. This recipe is meant as a contribution to that
  feedstock: more platforms, and outputs that depend only on what they use. GeoModel's CMake
  turns warnings into errors; the recipe turns that off. 3 minutes. Tests: a small geometry
  written to SQLite and read back (through the CMake configuration), and a GeoModelXml
  description turned into SQLite by `gmcat` with GMXPlugin.
- **`atlas-acts` 47.7.0**: the Json, GeoModel and Root plugins and Fatras, C++23, like
  AthenaExternals. One package: ACTS's installed CMake configuration lists every component it
  was built with and loads all of them, and it requires the exact Boost, Eigen, nlohmann_json,
  ROOT and GeoModel versions it was built against (`EXACT`), so split outputs would need
  patches, and the run requirements are pinned to x.x.x. The release archive ships the
  generated code, so no Python is needed (`ACTS_CODEGEN_REQUIRE_PREBUILT`), and
  `ACTS_COMPILE_HEADERS=OFF` skips ACTS's compile-every-header check. 11 minutes, 5 MB.
  `run_constraints: acts-core <0a0` (same files). Test: a surface written to JSON and read back,
  a straight line intersected with it, a GeoModel material converted (X0 of iron).
- vecmem is not needed before the trigger and GPU packages.

**Eigen.** conda-forge's global pinning has moved to Eigen 5 (`eigen_abi_devel` 5.0.1), and a
plain `eigen` host dependency resolves to 5.0.1. ATLAS builds with Eigen 3.4.1, and Eigen 5 is
not API compatible (Athena's `EventPrimitivesHelpers.h` relied on Eigen/Core including
`<cassert>`). geomodel, atlas-acts and the Athena layers now build against `eigen-abi-devel`
3.4.0.100 (Eigen 3.4.0), whose run export keeps them from being mixed with Eigen 5 builds.

**The layer contents.** The M4 deliverable is DumpGeo: `python -m DumpGeo.DumpGeoConfig` builds
the whole ATLAS geometry for a tag and dumps it to a GeoModel SQLite file. Its configuration,
run in ATLAS's own release from CVMFS (the new `athena-ref` container,
`athena-notes/cvmfs-athena.sh`, `analysis/scripts/cfgdeps.py`), uses 43 python packages and 45
component types. Mapped to layers, 11 packages were in later layers: the alignment and
detector-element conditions algorithms (CaloAlignmentAlgs, LArAlignmentAlgs, MuonCondAlg,
PixelConditionsAlgorithms, SCT_ConditionsAlgorithms, TRT_ConditionsAlgs) and python-only
configuration packages (MuonConfig, LArConfiguration, TrkConfig, ActsConfig,
OverlayConfiguration, TriggerJobOpts). They are now explicit seeds of `detdescr` in
`layers.py`, as are GeneratorConfig and McEventSelector for `core` (which changes nothing in
core). detdescr: 219 packages, 1,797 TUs; nothing needs a later layer at build time.

**Runtime data.** The geometry comes from the ATLAS geometry database, and the job also reads
conditions (alignment). Both are read through Frontier; ATLAS's public server answers direct
requests from here (the proxy `asetup` adds answers 403), and conditions payloads come from
CVMFS. The geometry databases on CVMFS (DBRelease `geomDB_sqlite`, 123 MB, 2022; GroupData
`Geometry/*.db`, 51 MB DEV tags) have no clear licence and are not packaged. So the geometry
test runs only where CVMFS is mounted; the identifier test needs nothing.

Reference numbers (ATLAS's release, aarch64): DumpGeo for ATLAS-R3S-2021-03-02-00 takes 3
minutes and writes 58,181 PhysVols, 26,226 FullPhysVols, 59,048 LogVols and 485 materials
(30 MB); `gmcat` reads it back unchanged.

**`athena-detdescr`** (project `AthenaDetDescr` on `AthenaCore`) builds with rattler-build on
linux-aarch64 and passes:
- **the ATLAS geometry**: DumpGeo for ATLAS-R3S-2021-03-02-00 builds every subdetector's
  GeoModel description (beam pipe, Pixel, SCT, TRT, ID services, LAr, Tile, muons) and dumps it.
  The result is **identical in size to ATLAS's own release** (the counts above), and `gmcat`
  reads it back unchanged. 1.5 minutes. It needs CVMFS and network (Frontier), so it is skipped
  elsewhere;
- **identifiers**: SCT and pixel identifiers from the release's ID dictionaries through PyROOT
  (a port of ATLAS's SCT_ID unit test, checked against ATLAS's release first);
- the component check: 527 components, and every one has its configurable.

Fixes on the way, in the recipes below the layer:
- **`env_setup.sh`**: the layer projects now generate and install it, as `Projects/Athena`
  does. It carries the environment that packages register (`CORAL_DBLOOKUP_PATH` and
  `CORAL_AUTH_PATH` from AtlasAuthentication, `UBSAN_OPTIONS` from CxxUtils,
  `COOL_DISABLE_CORALCONNECTIONPOOLCLEANUP`, ...), and CORAL needs `dblookup.xml` to resolve
  logical database names such as `ATLASDD`. Paths into the build environment are rewritten to
  the environment's prefix. The activation scripts save and restore the new variables.
  `CORAL_AUTH_PATH` points at a directory with no `authentication.xml`, which is fine for
  Frontier and SQLite.
- **`frontier-client`** had no `run_exports`, so CORAL's Frontier plugin could not load
  `libfrontier_client.so.2` at runtime (CMSSW's copy of the recipe has the same gap).
- The deactivation scripts unset the `<project>_*` variables of every layer.

**Cost** (`compile_cost.py`): 1,859 compiles at 5.6 CPU-s on average (2.9 CPU-h) plus about 1
CPU-h of dictionaries: about 4 CPU-h, as `layers.py` predicted, so 2–2.5 h on a 2-core runner.
The whole recipe takes 40 minutes at `-j10` here, tests included. Peak RSS per compile:
median 0.5 GB, p90 1.25 GB, max 1.9 GB (ACTS and Eigen code, the MuonCondAlg component
list): `-j4` still fits in 7 GB. The slowest single step is again a reflex dictionary
(`xAODMuonPrepData`, 6–11 minutes of genreflex). Package: 39 MB.

**Next:**
- the `edm` layer (xAOD and trigger EDM; read AOD/DAOD in Athena and PyROOT), the rest of M4;
- runtime data without CVMFS (D6): the geometry database. The DBRelease `geomDB_sqlite` or a
  GeoModel SQLite geometry per tag would make the geometry test run anywhere, but needs ATLAS's
  agreement on the licence, like a default `FRONTIER_SERVER`;
- still open from M3: the runtime python dependencies of core, the licences of CORAL, COOL,
  CrestApi and yampl.

### 2026-10-09: the edm layer (M4, second part)

**The layer contents.** `layers.py` put the event data classes, their T/P converters, POOL
converters and dictionaries in `edm` (166 packages), but not two packages that event data I/O
needs, because they have algorithms and tools and the layer forbids components:
- `xAODTrackingAthenaPool` (the converter of `xAOD::TrackParticle`, in every AOD and DAOD)
  includes an interface header of `xAODTrackingCnv`, whose algorithms link `MCTruthClassifier`
  and its calorimeter and particle-flow tools;
- writing a data file's metadata needs `LumiBlockComps` (the luminosity block metadata tool).

A new `tool_seeds` entry in `layers.py` lets these two in with their closure (+21 packages,
+135 TUs, no new externals). edm: 187 packages, 1,739 TUs; nothing needs a later layer.
The third metadata tool a DAOD copy uses, the trigger menu's (`xAODTriggerCnv`), stays out:
in Athena mode that package brings the trigger decision and steering packages (+26 packages,
+395 TUs, L1Topo's algorithms, which download two ML models at build time). Found by running
the test job in ATLAS's release with `cfgdeps.py` (which now also takes a job script) and the
new `cfgmap.py` (configuration → packages → layers).

**Test data.** ATLAS Open Data has DAOD_PHYSLITE files under CC0 (opendata.cern.ch records
80000–80020). The smallest are tails of runs: `DAOD_PHYSLITE.37001701._000001.pool.root.1`
(2015 data, run 276183, 132 events, 1 MB) is a second source of the recipe, downloaded with a
sha256 like any source. The ATLAS test files on CVMFS (`data-art/ASG`, the old AODs of the
T/P tests) have no clear licence and are only read in place.

**`athena-edm`** (project `AthenaEDM` on `AthenaDetDescr`) builds on linux-aarch64 and passes:
- **xAOD I/O without CVMFS**: Athena reads the Open Data file and dumps every object in it with
  PyDumper (127,173 lines), and writes a copy with all its event data and its metadata
  propagated (file metadata, cut bookkeepers, luminosity blocks, event format; not the trigger
  menu); Athena reads the copy back. Both dumps are **identical to the dump ATLAS's own release
  writes** (shipped as `test/data15_physlite.dump.xz`, 120 kB). PyROOT reads both files through
  `xAOD::MakeTransientTree`, objects and element links (electron to track and cluster, muon to
  track), and gets the same summary as ATLAS's release;
- **ATLAS's T/P converter tests** of the layer's packages (`run_tpcnv_test`, 38 of 46): AODs
  written by releases 15 to 21 read with the current classes and compared with ATLAS's
  references, when CVMFS is there (`tpcnv_tests.py` lists them). The other 8 (`RecTPCnv`,
  `TrackParticleTPCnv`) configure geometry and conditions that need the reco and edm-det
  layers; all 46 pass in ATLAS's release;
- the component check: 1,424 components, 745 configurables.

Fixes on the way, in all the layers (core and detdescr rebuilt, tests still pass):
- **`-fvisibility-inlines-hidden`** (from conda-forge's `CXXFLAGS`) is now stripped. ATLAS does
  not use it, and its libraries export inline functions that other libraries link to:
  `DATAVECTOR_BASE_FIN` defines `SG::bi_destroy<DataVector<T>>::destroy` inline in the class's
  header, and code that sees only `DATAVECTOR_BASE_FWD` (VxJetVertex) linked to the copy in
  `libxAODTracking.so`, which was hidden. The same thing that CMSSW patch 0006 works around, but
  here it is the project's own convention.
- **CLIDs of the layer's types.** AtlasCMake writes `clid.db` from the component libraries only,
  so a type is in it when some component's code uses the type: in ATLAS's release that is often
  a reconstruction or trigger component, in a later layer here. Without it Athena could not
  name `xAOD::MissingETContainer`, `xAOD::EventShape` or `xAOD::TrigConfKeys` objects in a DAOD.
  The layer `CMakeLists.txt` now runs `genCLIDDB` on every POOL converter library too and adds
  the result to the project's merged `clid.db` (core's grew from 250 to 268 entries).
- The `athena-ref` container needed libuuid-devel (cling parses `uuid/uuid.h`), libbrotli
  (ROOT's TreePlayer) and diffutils (ATLAS's tests).

**Cost** (`compile_cost.py`): unlike the first two layers, **dictionaries dominate**. 482
genreflex steps took 6.2 h of summed wall time against 3.7 h for the 1,822 compiles (at `-j10`
on 10 cores, so inflated by contention); the slowest is `xAODTrigL1CaloDict` (16 minutes, then
`xAODTauDict` 7, `TrigMuonEventDict` 6, `egammaEvent` 5). The whole recipe takes 50 minutes here,
tests included: at most 8 CPU-h, about twice `layers.py`'s estimate, which counts a dictionary
as one TU. Peak RSS per compile: median 0.46 GB, p90 1.4 GB, max 3.0 GB (the trigger EDM's
`*StorageDefinitions.cxx` and the converter component lists, 2.4–3.0 GB): `-j2` or `-j3` on a
7 GB runner. Package: 49 MB.

**Next:**
- the `edm-det` layer (RDO/ESD/HITS), the end of M4; its T/P tests and the 8 above;
- open: the trigger menu metadata tool (with the trigger decision tool, in `analysis`), a
  default `FRONTIER_SERVER` and the geometry database without CVMFS (D6), the runtime python
  dependencies of core, the licences of CORAL, COOL, CrestApi and yampl.

### 2026-10-09: the edm-det layer (M4, last part)

**The layer contents.** `layers.py`'s edm-det (131 packages) lacked what a job reading HITS, RDO
and ESD files needs at run time, found by running the test job in ATLAS's release (with
`cfgdeps.py`, and by listing the libraries the process loads):
- `G4SimAthenaPOOL`, the converter of the track records (`CaloEntryLayer`, ... in every HITS
  and RDO file), was in sim: the seed and absorb patterns matched `AthenaPool`, not ATLAS's
  spelling `AthenaPOOL`;
- new tool seeds: `InDetEventCnvTools` and `MuonEventCnvTools` (the `Trk::Track` converters
  find the detector elements of measurements through them: ESD reading and the unit tests of
  MuonEventTPCnv), `CaloCondAthenaPool` with `CaloTriggerTool` (the LAr alignment,
  `CaloAlignCondAlg` in detdescr, reads `CaloRec::CaloCellPositionShift` through it: no job
  that builds the aligned calorimeter geometry ran without it) and `HepMCWeightSvc` (the
  `McEventCollection` converters of edm use it for the generator weights).

edm-det: 137 packages, 1,260 TUs; nothing needs a later layer. New external: FastJet
(EventShapeEvent's headers use `fastjet::RangeDefinition`). As in the CMSSW project,
`fastjet-cxx ==3.5.1 *_5` (ATLAS's version) is pinned: since build 6 the headers are in
`fastjet-cxx-devel`, which requires `cgal-cpp`, and no `cgal-cpp` goes with both Boost 1.90 and
Eigen 3.4 (the 1.90 builds need eigen-abi 5).

**Unit tests at build time.** ATLAS's compiled tests of the T/P converters (round trips of
transient objects through each persistent version) need no input files. `build.sh` builds the
`Package_<name>_tests` targets of the packages in `unit_tests.txt` (41 of the layer's) and runs
them with ctest, which labels each test with its package, excluding the packages' T/P converter
tests (CVMFS and the geometry database; the recipe's tests run those). **All 364 pass**; about
300 more TUs. One needed a fix in core: `athena.py` is a `#!/bin/sh` script with bash arrays,
and fails where `/bin/sh` is dash (Debian, Ubuntu, this container); core's patch 0003 makes it
`#!/bin/bash` (upstreamable; core rebuilt, its HelloWorld test now runs `athena.py` directly).

**`athena-edm-det`** (project `AthenaEDMDet` on `AthenaEDM`) builds on linux-aarch64 and passes:
- **HITS, RDO and ESD I/O**, with CVMFS: ATLAS's Run 3 test files (`TestDefaults` HITS_RUN3,
  RDO_RUN3, ESD_RUN3_MC; licence unclear, read in place). Athena reads 2 events of each, dumps
  every object with PyDumper (sim hits of every subdetector, the raw data and sim data of ID,
  calorimeters and muons, calorimeter cells, prepared data, tracks: 147k, 587k and 2.25M lines)
  and writes a copy, which it reads back and dumps. **All six dumps are identical to the ones
  ATLAS's release writes**; the recipe has their sha256 sums only. The copies differ from their
  inputs in ATLAS's release too: silicon hit positions lose precision in their persistent form,
  and ESD truth links are lost when the file has no truth event. The jobs build the geometry
  from the files' tags, through Frontier;
- **ATLAS's T/P converter tests** (CVMFS), 33 here (29 of the layer, 4 of edm's track particle
  converters): 23 pass. The 4 without a reference tag look for their reference in
  `../share/`, which only exists in a build tree (they fail in ATLAS's installed release
  too); the recipe ships those references, from the source. 9 need the reco layer (the `Reco`
  flags of RecJobTransforms, CaloRec's `CaloTopoTowerBuilderTool`); `TrkEventTPCnv_14.5.0`
  fails in ATLAS's release too (CSC measurements without detector elements);
- the component check: 857 components, 754 configurables.

The activation scripts run alphabetically, so `athena-edm-det`'s before `athena-edm`'s. That is
harmless: each `setup.sh` returns early when its project is already set up
(`<Project>_SET_UP`).

**Cost** (`compile_cost.py`): 1,686 compiles (unit tests included) took 2.9 h of summed wall
time at `-j10`, dictionaries 0.5 h; about 3 CPU-h in all, as `layers.py` predicted. The whole
recipe takes 50 minutes here: 21–27 for the build with the unit tests, 22 for the tests (the
ESD job most of it).
Peak RSS per compile: median 0.54 GB, p90 1.7 GB, max 2.6 GB (the converter component lists of
MuonEventAthenaPool and LArCondAthenaPool): `-j2` or `-j3` on a 7 GB runner. Package: 23 MB.

**M4 is done**: the geometry builds, and AOD/DAOD (Athena and PyROOT), HITS, RDO and ESD are
read and written as in ATLAS's release.

**Next:**
- M5, the `analysis` layer (CP tools on DAOD_PHYSLITE, ATLAS Open Data), with the trigger menu
  metadata tool and the trigger decision tool;
- the T/P tests deferred to reco (13: edm's 4 RecTPCnv and the 9 above);
- open: a default `FRONTIER_SERVER` and the geometry database without CVMFS (D6; every test of
  this layer needs both), the runtime python dependencies of core, the licences of CORAL,
  COOL, CrestApi and yampl; upstream the athena.py shebang.

### 2026-10-10: the analysis layer (M5)

**The layer contents.** `layers.py`'s analysis layer (the AthAnalysis project's packages, built
in Athena mode) had everything that CP algorithm jobs on DAOD_PHYS and DAOD_PHYSLITE load: three
jobs run in ATLAS's release with the libraries and python packages they load listed (the Open
Data job below and two of ATLAS's own CP tests) needed nothing from a later layer (one
library of `rest`, `DataQualityInterfaces`, is a ROOT autoload only). Added: `Asg_Test` (the
`ASG_TEST_FILE_*` variables of ATLAS's analysis tests and examples, no dependencies). 169
packages, 1.6k TUs. New externals, all from conda-forge: onnxruntime-cpp 1.26 (cpu), lwtnn,
fastjet-contrib, HDF5, lz4, LHAPDF, nanobind, and PyYAML at run time (`CPRun.py` and every
YAML configuration of the CP algorithms import it).

**Fixes:**
- **`ROOT_FOUND` was false in every layer.** AtlasLCG's FindROOT requires ROOT's python modules
  in `<ROOT>/lib`; conda-forge has them in `site-packages`. Nothing noticed until a package
  asked for ROOT with `REQUIRED` (HyPERAnalysisAlgorithms). athena-externals' PostConfig now
  sets `ROOT_PYTHON_PATH`; all layers were rebuilt with it and pass their tests.
- **Find modules for conda-forge's layouts** (athena-externals): `FindFastJetContrib` (one
  `libfastjetcontribfragile` instead of LCG's library per contrib) and `Findonnxruntime`
  (conda-forge has the API headers in `include/onnxruntime/core/session/`, Microsoft's tarball
  in `include/`). Each project installs a copy of its base's find modules, so such a change
  needs every layer rebuilt (CLAUDE.md).
- **Triton** (inference on a server; not on conda-forge): FlavorTagInference builds its Triton
  service only where the client is found (analysis patch 0001); the flag that selects it,
  `BTagging.UseTriton`, is off by default and the ONNX path is unchanged.
- **GroupData without CVMFS.** The CP tools read calibration files through PathResolver from
  `CALIBPATH`, which PathResolver's environment sets as in ATLAS's release: CVMFS, EOS, then
  ATLAS's web servers. A file is taken from a web server only with
  `PATHRESOLVER_ALLOWHTTPDOWNLOAD`, which athena-core's activation now sets (if unset); it is
  downloaded to the job's working directory. PathResolver saved an HTTP error page as the file
  and left an empty file behind after a failed download (one of the two web servers answers
  404 for everything): core patch 0004 (upstreamable). Core's new test resolves a file from
  CVMFS and downloads it, and checks that a missing file leaves nothing behind.

**`athena-analysis`** (project `AthenaAnalysis` on `AthenaEDMDet`) builds on linux-aarch64 and
passes:
- **ATLAS's unit tests at build time**: 78 tests of 31 packages, those that need no input
  files, CVMFS or network (checked in a container with neither); the 21 others of those
  packages and all tests of the other packages read ATLAS's test files (CVMFS), GroupData or the
  geometry database, or need later layers. onnxruntime prints a warning in containers where it
  cannot tell the CPU's vendor, which breaks reference comparisons: `build.sh` sets ATLAS's
  ignore pattern for it;
- **an analysis of ATLAS Open Data with the CP algorithms** (`CPRun.py`, `test/opendata_data15.yaml`
  from ATLAS's Run 2 test configuration): the 2015 DAOD_PHYSLITE file of the edm layer, with
  the good-runs list, calibrated and selected muons, electrons, photons, taus, small- and
  large-R jets with flavour tagging (DL1dv01, the tagger of the Open Data files), tracks,
  missing transverse momentum, overlap removal, trigger decisions and trigger matching. The
  n-tuple (116 events, 80 branches) is **identical to the one ATLAS's release writes**,
  including with the calibration files downloaded instead of read from CVMFS. This needs
  **no CVMFS**, but network: GroupData (44 MB) from ATLAS's web server, and the geometry
  database through Frontier (the configuration looks up the LHC period of the file's geometry
  tag);
- with CVMFS, **two of ATLAS's own CP tests** on its MC test files: TestCPRunFullSim (DAOD_PHYS,
  150 events: every object with its systematic variations, scale factors and truth; 5,130
  branches, identical to ATLAS's) and TestCPRunPhysliteLikePhyslite (DAOD_PHYSLITE, 1,000
  events on 4 threads, no errors). With threads, CP jobs that write n-tuples fail in ATLAS's
  release too (the n-tuple makers' data dependencies); ATLAS's multi-threaded test writes none;
- the component check: 1,198 components, 1,511 configurables.

**Cost** (`compile_cost.py`): 1,622 compiles took 4.9 h of summed wall time at `-j10`,
dictionaries 1.3 h: about 5 CPU-h, within `layers.py`'s 3.7–6.9 h. The recipe takes 38 minutes
here: 35 for the build with the unit tests, 3 for the tests. Peak RSS per compile: median 0.8
GB, p90 1.6 GB, max 3.3 GB (TrigOutputHandling's `HLTEDMCreator.cxx`, then the component lists
of the CP algorithm packages, 2.1–2.6 GB): `-j2` on a 7 GB runner. Package: 76 MB.

**M5 is done**: ATLAS's CP tools analyse DAOD_PHYSLITE in a conda environment as in ATLAS's
release, without CVMFS.

**Next:**
- M6: reco-tracking, reco and trigger;
- open: a default `FRONTIER_SERVER` and the geometry database without CVMFS (D6; even the Open
  Data analysis needs the geometry database, for the LHC period), the licences of CORAL, COOL,
  CrestApi and yampl; upstream the athena.py shebang, PathResolver's downloads and
  FlavorTagInference's optional Triton.

### 2026-10-11: reco-tracking, reco and trigger (M6)

**The layer order.** `layers.py` had sim (Geant4) before the reconstruction layers, which took
46 (reco-tracking) and 156 (reco) packages from it. All of those were sim's non-Geant4 part
(monitoring, the muon reconstruction interfaces, fitter utilities, digitization configuration),
which it had absorbed. reco-tracking, reco and trigger now come before sim, take those packages
themselves and forbid Geant4 and the generators (`NO_SIM`); sim waits for D5. Then, as for the
earlier layers, the jobs each layer delivers were run in ATLAS's release with `cfgdeps.py`:
- **reco-tracking** (241 packages): ATLAS's ID tracking test (`python -m
  InDetConfig.TrackRecoConfig`) also configures `TrackToVertex` and `TrkParticleCreator`, and
  imports python configuration from RecJobTransforms, DigitizationConfig, TrackOverlayConfig and
  DerivationFrameworkInDet: explicit seeds. `TrkParticleCreator` and the ACTS track
  reconstruction link four muon interface packages, which reco-tracking now allows.
- **reco** (324 packages): `Reco_tf.py` from RDO to ESD and AOD also uses `MCTruthAlgs` (the
  muon truth's track record filter) and `RunDependentSimComps` (pile-up helpers the
  digitization flags import), and the trigger configuration flags (TriggerJobOpts) import
  `TriggerMenuMT` and `TrigHLTMonitoring` even with the trigger off: seeds.
- **trigger** (176 packages): the HLT on simulation (`python -m TriggerJobOpts.runHLT`, the
  Dev menu) also needs `AnalysisTriggerAlgs` (the L1 result's xAOD conversion) and
  `MuonByteStreamCnvTest` (the RDO-to-digit algorithms of the L1 muon simulation). Its other
  imports from later layers are optional flag categories (`moduleExists`). Left out: the
  GPU/FPGA code (vecmem, Xilinx HLS types) and the online packages (ByteStreamEmonSvc needs
  the TDAQ release; TrigByteStreamCnvSvc and TrigDFEmulator tdaq-common's `df_ef_interface`,
  which has no licence file; TrigServices, athenaHLT's services, tdaq-common's `webdaq`).
- `UNDECLARED_EXT` in `layers.py` sends packages that need unpackaged externals the graph does
  not show to the last layer: those above, and `ITkPixelByteStreamCnv` (Phase-II), which
  includes `itksw-endec` (built by AthenaExternals) without declaring it.
New externals: BLAS/LAPACK, FFTW, libtirpc (reco-tracking); none for reco and trigger.

**Tests**, all on ATLAS's Run 3 RDO test file (CVMFS, read in place) through Frontier, outputs
dumped with PyDumper and compared with ATLAS's release:
- reco-tracking: ATLAS's ID tracking job on 10 events, its AOD output (track particles,
  vertices, ...): **identical** (419,547 lines);
- reco: `Reco_tf.py` (calorimeters, inner detector, muons, e/gamma, jets, taus, particle flow,
  b-tagging, MET) on 5 events: ESD (1.73M lines) and AOD (406k lines) **identical**;
- trigger: the HLT with the Dev menu (`Dev_pp_run3_v1_TriggerValidation_prescale`, as ATLAS's
  `test_trig_mc_v1Dev_build`) on 5 events, RDO to RDO_TRIG: the L1 simulation and every HLT
  chain; the chain counts (`TrigSignatureMoni`, 111 chains), which ATLAS's trigger tests check,
  are **identical** to the release's;
- the component checks: reco-tracking 1,318 components (2,268 configurables), reco 1,711
  (3,552), trigger 1,093 (4,302).

**Fixes on the way:**
- **Prefix replacement and string tail merging (all layers).** `__FILE__` of headers in the
  host prefix (`AthCommonDataStore.icc` and the like) puts the prefix in the libraries'
  read-only strings, which packaging rewrites in place: a shorter prefix, padded with NULs.
  GNU ld stores a string literal that is the tail of another one inside it, so such a literal
  points into the rewritten string and becomes empty. The HLT failed on it:
  `BJetThreeValueCheck`'s property name `"c"` lived at the end of `".../AthCommonDataStore.icc"`,
  so the property could not be set (`SG::ExcBadVarName`), only in the packaged library. Found by
  comparing the packaged library with the build tree's, and reproduced by relocating a
  library as packaging does (`analysis/scripts/relocate.py`; `prefixstrings.py` counts the
  prefixed strings of a layer). `-fno-merge-constants`
  does not help: `arm_neon.h`'s `#pragma GCC push_options`/`target` restores the default. The
  layers now map the prefix in `__FILE__` (`-fmacro-prefix-map=$PREFIX=/usr/local/src/conda-prefix`,
  as conda-forge's flags do for debug information), which leaves no prefixed strings but a
  handful; every layer was rebuilt with it. This can bite any conda package built against
  headers in the prefix; worth raising with conda-forge.
- **authentication.xml in the sources.** `PixelConditionsTools/share/` has one with credentials
  (in ATLAS's public repository), and the install area carries the packages' sources: the guard
  stopped the build. All layers now drop it from the sources they ship.
- **chai's headers** go to `include/chai/` (as in the TDAQ release's externals): LArCalibUtils
  asks for chai as a tdaq-common component (`find_package( tdaq-common COMPONENTS chai
  chaicontainer )`), with tdaq-common's include directory. A find-module fix would not have
  reached the layer: every project's configuration puts its own copy of the find modules first
  again (AtlasCMake's configuration, loaded from each project), whatever the layer project does.
- **clhep** (feedstock change, `athena-notes/feedstock-changes/clhep`): conda-forge builds it with
  `-fvisibility-inlines-hidden`, which hides GenericFunctions' `clone()` (defined inline in its
  `.cc` files): LArG4Validation did not link. Rebuilt without the flag (2.4.7.1, build 1).
- **CaloRecGPU** installs nothing without CUDA, its configuration flags included, but the
  trigger's calorimeter configuration reads `flags.CaloRecGPU` unconditionally: reco patch 0001
  installs its python modules without CUDA too (upstreamable).
- **Runtime dependencies**: `psutil` (PerfMon, which the transforms switch on), `procps-ng` and
  `prmon` (PyJobTransforms), in athena-core; the CREST python client (`pycrest-client`, new
  recipes with `hep-crest-client`, Apache 2.0 in their metadata but no licence file, like
  CrestApi) for the trigger configuration.
- Test jobs that fail the transform after Athena finished: without `ps`, Reco_tf.py's
  post-processing crashed and left ESD/AOD files that could not be read back.

**Cost** (`compile_cost.py`, `-j10`, with other jobs running):
- reco-tracking: 1,296 compiles, 5.7 h summed wall; peak RSS median 0.95 GB, p90 2.0 GB, max
  2.7 GB (the ACTS track reconstruction). Recipe 41 minutes, package 63 MB.
- reco: 2,111 compiles, 8.5 h summed wall; peak RSS median 0.94 GB, p90 1.9 GB, max 3.0 GB
  (TGC raw data monitoring). Recipe 66 minutes, package 110 MB.
- trigger: 1,502 compiles, 4.3 h summed wall (built alone); peak RSS median 0.7 GB, p90 1.9 GB,
  max 3.0 GB (the rates analysis, tau and e/gamma trigger monitoring). Recipe 38 minutes,
  package 64 MB.
All three `-j2` on a 7 GB runner; reco, at about 9 CPU-h, is the tightest layer for a 6-hour job.
The rebuild of the whole chain with the prefix fix took 4.4 hours here (core 11 minutes, detdescr
20, edm 32, edm-det 41, analysis 39, reco-tracking 35, reco 63, trigger 38), every layer passing
its tests.

**M6 is done**: `Reco_tf.py` reconstructs RDO into ESD and AOD, and the HLT runs on simulation,
in a conda environment with results identical to ATLAS's release (with CVMFS for the test file
and conditions payloads). The eight layers hold 1,632 of the release's 1,966 packages and 83% of
its translation units.

**Next:**
- M7: sim (Geant4, D5), the rest (derivations, data quality, event display), an `athena`
  metapackage and the developer workflow;
- the unit tests of the M6 layers at build time (as for edm-det and analysis);
- raise the prefix replacement/tail merging hazard with conda-forge, the clhep visibility change
  with its feedstock, and the credentials in PixelConditionsTools' sources with ATLAS;
- open: a default `FRONTIER_SERVER`, the geometry database and conditions payloads without CVMFS
  (D6), licences (CORAL, COOL, CrestApi, the CREST python clients, yampl); upstream the patches.

### 2026-10-12: sim, rest, the metapackage and the developer workflow (M7)

**Geant4 (D5): ATLAS's fork.** `atlas-geant4` builds the ATLAS simulation team's Geant4
10.6.3.15 with atlasexternals' four patches, and VecGeom 1.1.21 with its three, as
AthenaExternals does: static, multithreaded, GDML, VecGeom's cons and polycone, and link-time
optimization (`build_externals.sh` turns it on for both). The objects are fat, so consumers can
also link without LTO. It conflicts with conda-forge's geant4 and vecgeom; the data sets are
conda-forge's `geant4-data-*` in the 10.6 versions. The layers set `ATLAS_GEANT4_USE_LTO` from
CMake's IPO check, as Projects/Athena does: the first layer writes it into its
PreConfig.cmake, where it had been empty, so AtlasGeant4 was linked without LTO.

**New externals:** `tdaq-dqm-core` (tdaq-common 14.0.0's dqm_core, on the tdaq-common recipe's
CMake shim plus a ROOT shim: the data quality algorithms and the histogram assessment) and
`atlas-rivet` (conda-forge's rivet recipe and patches, on `fastjet-cxx` 3.5.1 build 5:
conda-forge's rivet needs `fastjet-cxx-devel`, whose `cgal-cpp` does not exist for Boost 1.90
and Eigen 3.4).

**What is not packaged.** `layers.py` has a "none" pseudo-layer: the packages that compile
against an external no conda package provides (`UNAVAILABLE_EXT`: the generators conda-forge
lacks, the GPU stack, the TDAQ release; `UNAVAILABLE_PKG`: Triton's client; `UNDECLARED_EXT`),
and everything that depends on them. Packages without C++ sources are exempt for the generators
(they only look up the generator's runtime environment) but not for the GPU stack (interface
libraries that link `vecmem::core`, and SYCL sources, which are not counted as C++): the rest
layer's configure step found those. 30 packages, 174 translation units. The eight earlier layers
are unchanged.

**sim** (155 packages): Geant4 simulation of every subdetector, ISF with FastCaloSim and Fatras,
the generator interfaces that conda-forge's generators allow (Pythia8, LHAPDF, Rivet), and
`Sim_tf.py`. **rest** (149 packages, the project `Athena`): the derivation framework,
D3PDMaker, data quality, VP1, physics validation, test beam, examples and tests.

**Tests.**
- sim: ATLAS's `test_RUN3_FullG4MT_QS_ttbar_MT` set-up (FullG4MT_QS, MC23e), 3 events of the
  ttbar EVNT test file, serially. The HITS file is dumped with PyDumper and compared with the
  release's dump (`compare_sim.py`). The generator record after the beam spot smearing must be
  identical event by event, and it is. Every hit collection's size, summed over the events, must
  be within 20% for those with at least 1,000 entries. All are within 10%: Pixel +5%, SCT +9%,
  TRT -5%, LAr EMB +2.5%, HEC +6%, Tile -0.5%.
- rest: `Derivation_tf.py` to DAOD_PHYS and DAOD_PHYSLITE from 10 events of the Run 3 ttbar
  AOD, both dumps compared with the release's by sha256: **identical** (DAOD_PHYS 103,957
  lines, DAOD_PHYSLITE 30,831).

**The simulation is not identical to the release.** With everything below fixed, the first
Geant4 vertices agree with ATLAS's and the events diverge after about the sixth, a few metres
into the detector. Checked and ruled out by running variants of the job:
- the C library: the packaged layer in the EL9 container gives the same output as on Ubuntu;
- the allocator: tcmalloc in both;
- the Geant4 data sets: identical files;
- VecGeom's and VecCore's configuration: identical;
- Geant4's link-time optimization;
- CLHEP (below).

Left: the compiler, and the builds of the other externals. The compiler is conda-forge's gcc
15.3 against LCG's 15.2; relinking with LCG's gcc fails because its LTO objects are
zstd-compressed and conda-forge's gcc has no zstd.

Our job also raises FPE INVALID and DIVBYZERO in the simulation in every event, and ATLAS's job
raises none. aarch64 has no floating point traps, so the FPE auditor only reports the flags per
algorithm. Jobs without the calorimeters, without the muon system, without the TRT or without
the silicon detectors all still raise them. The sim test leaves FPEs out of its log check. Next
steps: ATLAS's simulation experts, and linux-64 (with traps) will say more.

**Fixes on the way:**
- **The exported targets named the build environment.** Each layer's exported CMake targets
  named glibc's libraries by absolute path in that layer's build environment:
  - `libpthread.a`: AtlasLCG's FindROOT caches the `pthread` component in
    `_ROOT_pthread_library`, so the earlier `ROOT_pthread_LIBRARY` setting did nothing;
  - `libdl`/`libm`: CMake's FindHDF5, from HDF5's compiler wrapper.

  Later layers built only because the kept build trees still existed; removing them to free
  disk space showed it. athena-externals' PostConfig now gives these libraries by name, and
  every layer's `build.sh` fails when its CMake configuration names `$BUILD_PREFIX`. All layers
  were rebuilt.
- **`G4VERS`**: SimConfigFlags checks the Geant4 version name (`_check_G4_version`), which
  ATLAS's setup takes from its Geant4 installation; sim's activation sets it from
  `G4Version.hh`.
- **ReleaseData** (the LAr high-voltage maps) is found through `SITEROOT`/`ATLAS_RELEASEDATA`,
  which ATLAS's `setup.sh` points at `/afs`. sim's and rest's activation point them at CVMFS
  when it is mounted. conda runs activation scripts alphabetically, so athena-analysis' setup
  has already set them: the check is whether the directory exists. ReleaseData has no clear
  licence and is not packaged.
- **The Geant4 random stream had no name in the packaged library.** Its seeds are derived from
  `<client>/<stream>`, so they differed from ATLAS's, and so did every random number drawn from
  it. The literal `"Geant4"` (TransportTool's `RandomStreamName`) was stored as the tail of
  `$PREFIX/include/Geant4`, one of the include paths rootcling writes into a dictionary
  (ISF_FastCaloSimParametrization's, linked into AtlasGeant4), and packaging blanked it. This is
  the M6 hazard again, outside `__FILE__`. `-Wl,-O0` does not stop the tail merging.
  athena-externals' patch 0004 runs rootcling with `--noIncludePaths`, as AtlasCMake already
  does for genreflex. It reached sim only after every layer was rebuilt: each project carries a
  copy of AtlasCMake's modules, like the find modules.
- **CLHEP**: ATLAS's fork draws RandGaussZiggurat's uniform numbers in double precision
  (`CLHEP_2_4_7_1_atl01`, ATR-26831). In single precision a number just below 1 rounds to 1,
  and the tail algorithm takes `log(0)` and draws a different count of numbers from the shared
  engine. The clhep feedstock change carries the fix as a patch (build 2). It did not remove the
  FPEs or the divergence.
- **Oracle**: DQUtils links Oracle's client without using it, and nothing provides it: rest
  patch 0001 drops it (upstreamable).
- **`which`**: athena.py calls it, and minimal EL9 images (athena-ref) lack it: a run
  requirement of athena-core.

**The metapackage and the developer workflow.** `athena` (noarch) requires `athena-rest`, which
pins every layer exactly. `athena-devel` adds the compilers, CMake and the externals'
development packages (headers, link-time symlinks, CMake configurations), with ROOT and Boost
pinned to the builds the layers used. Its test is the developer loop on top of the release:
- ATLAS's `Projects/WorkDir` and AthExHelloWorld are taken from the release's sources;
- the tool's message is changed;
- the work area is configured and built against the installed layers;
- its `setup.sh` is sourced, and `athena.py` prints the changed message.

It passes. Three things on the way:
- athena-devel needs the layers' `variants.yaml` (`root_cxx_standard` 23, ...), or its pins do
  not match the layers.
- `c-compiler`/`cxx-compiler` brought gcc 16, while the layers are gcc 15 builds: the
  `std::format` ABI problem again for any code using it. athena-devel now requires
  `gcc_<platform>`/`gxx_<platform>`/`gfortran_<platform>` in the pinning's major.
- The layers are built with the glibc 2.34 sysroot, but `root_base` requires the 2.17 one
  (`sysroot_linux-aarch64 2.17.*`, for cling), so a user environment cannot have 2.34. Work
  areas compile against glibc 2.17's headers. Components link, but executables that link a
  layer library fail (`undefined reference to dlopen@GLIBC_2.34`) unless they are linked with
  `-Wl,--allow-shlib-undefined`, as checked in an athena-devel environment. athena-devel could
  add the flag in an activation script.

`athena`'s test runs HelloWorld with every layer activated. With a local channel, mamba solves
the athena-devel environment only with flexible channel priority (rattler-build solves it
either way).

**Cost** (`compile_cost.py`, `-j10`):
- sim: 1,095 compiles, 1.7 h summed wall (2.0 h for the whole ninja log); peak RSS median
  0.6 GB, p90 1.25 GB, max 1.8 GB (GeneratorFilters' component list, the ACTS Fatras tools).
  Recipe 23 minutes. The package is 323 MB: AtlasCMake installs the object files of the
  simulation packages (640 MB, `objects-Release`, as in ATLAS's release on CVMFS) so that a
  work area can relink AtlasGeant4.
- rest: 1,256 compiles, 2.6 h summed wall (3.1 h); peak RSS median 0.65 GB, p90 1.6 GB, max
  2.5 GB (LArCafJobs, the derivation framework tools). Recipe 27 minutes, package 55 MB.
Both are the lightest layers: sim `-j3`, rest `-j2` to `-j3` on a 7 GB runner. Neither runs
unit tests at build time yet.

**M7 is done**: ten layers hold 1,936 of the release's 1,966 packages (99% of its translation
units), every layer passes its tests, `athena` installs them all and `athena-devel` builds a work
area against them. The simulation runs but is not identical to ATLAS's.

**Next:**
- why the simulation differs (ATLAS's simulation experts; linux-64, where FPEs trap);
- athena-devel: link flags for executables in work areas (glibc 2.17 sysroot);
- M8: linux-64 and osx-arm64;
- the unit tests of the M6 and M7 layers at build time;
- raise the prefix replacement/tail merging hazard (now also through rootcling's include
  paths) with conda-forge, the clhep changes with its feedstock, and the credentials in
  PixelConditionsTools' sources with ATLAS;
- open: a default `FRONTIER_SERVER`, the geometry database, conditions payloads and ReleaseData
  without CVMFS (D6), licences (CORAL, COOL, CrestApi, the CREST python clients, yampl);
  upstream the patches.

### 2026-10-12: M8 begins: linux-64 and osx-arm64

**Setup.** linux-64 builds in `athena-dev-amd64`, conda-forge's CI image under Rosetta, and
ATLAS's x86_64 release runs in `athena-ref-amd64` for references. osx-arm64 builds natively
under `_work/` (CLAUDE.md). Builds use at most 5 threads (the laptop stays usable), so the
emulated linux-64 builds are slow: Geant4 took an hour, Rivet three and a half.

**linux-64**: every external builds and passes its tests; the layers are building. The one
problem so far is libunwind's `unwind.h` (gperftools depends on libunwind on x86_64 only),
which shadows GCC's and has no `_Unwind_Ptr` (athena-core patch 0006, CxxUtils).

**The tests' references are per platform.** ATLAS's own x86_64 release, run on the tests' jobs,
does not reproduce the aarch64 references: tracking, ESD (edm-det), ESD/AOD (reco), DAOD_PHYS
and DAOD_PHYSLITE (rest) and the CP n-tuples differ in floating point digits, with the same
line counts. Reading a DAOD (edm) and the HLT counts (trigger) agree. The sha256 files and the
Open Data dump are now `<name>.<platform>.*`; the linux-64 ones come from ATLAS's x86_64
release (`athena-notes/refs.sh`). A platform without references (osx-arm64: ATLAS has no
release there) runs the jobs and says it cannot compare. Under Rosetta ATLAS's x86_64
release reports FPEs (e.g. AGDDtoGeoSvc's initialisation) that it does not on aarch64;
presumably an emulation artifact, so the reference runs skip the FPE log check (not checked
on real x86_64 hardware). The x86_64 simulation reference run lacked the Geant4 data sets:
the sim test's tolerances may make the aarch64 summary usable as is (to be seen).

**osx-arm64**: every external except yampl (vmsplice, futexes: Linux only) builds and passes
its tests, and so does athena-core: `athena.py` runs HelloWorld, serial and multi-threaded,
conditions, ByteStream and GroupData work, and every component has its configurable. What it
took:
- Compilers: clang 20, ROOT 6.40's (`variants.yaml`), with `-D_LIBCPP_DISABLE_AVAILABILITY`
  (conda-forge's libc++ 20 headers mark `std::from_chars` with an attribute that does not
  compile; libc++ 21's mark the time zone database unavailable even in inline code). AtlasCMake
  defaults to C++20 below clang 22, while ROOT's interface makes its users C++23: half the
  targets were each; patch 0005 makes it C++23. CMake's C++ module scanning needs
  clang-scan-deps: off everywhere.
- SDK: the local builds use the macOS 11.0 SDK. conda-forge's ROOT 6.40 ships C++ modules
  built against it, and cling then fails on the mach headers of any newer SDK (13.3 to 27),
  which `boost/thread` includes (dqm_core's dictionary, and Athena's). A user with only a
  current SDK hits the same: to be reported to the root feedstock.
- Library lookup: dyld ignores `LD_LIBRARY_PATH`, and SIP drops `DYLD_*` from every script
  started through `/bin/bash` or `/usr/bin/env`. AtlasCMake sets rpaths (to this layer's lib/,
  the layers' below and the prefix's; rattler-build makes them relative), `setup.sh` also
  sets `GAUDI_PLUGIN_PATH` and `ROOT_LIBRARY_PATH` on macOS, and the code that `dlopen`s bare
  names looks through `@rpath/` (CORAL, ers, EventStorage) or the prefix (Gaudi's python).
  AtlasCMake's private copy of `/bin/bash` is killed by current macOS (copies of system
  binaries are): it now links conda-forge's bash. CORAL and COOL install a copy of
  `/usr/bin/env` into bin/, which would shadow the system's and is killed: removed.
- libpython: conda-forge's python has the interpreter built in. A library linking
  libpython3.13.dylib then runs, inside python, against a second, uninitialised interpreter
  (macOS binds each symbol to a library), which crashed PyCoral and Gaudi::Application. The
  libraries look Python's symbols up in the process (`-undefined dynamic_lookup`; Gaudi's
  `Python::Module`, AtlasLCG's FindPython), and every executable loads libpython with
  `-needed_library` (conda-forge's `-dead_strip_dylibs` drops it otherwise). An experiment
  confirmed it: such a library works from python and from a C program, a libpython-linked
  one crashes in python.
- Case-insensitive file system: AtlasLCG's `FindVDT.cmake` answered ROOT's
  `find_dependency(Vdt)`, and ROOT was then not found; athena-externals defines `VDT::VDT`.
- Externals: tdaq-common (stat64, gethostbyname_r, semtimedop in circ, `uint`, a chrono
  conversion; python extensions as `.so`), CORAL/COOL (CMake 4 refuses the CMP0026 policy of
  their Darwin branch; `std::auto_ptr` and `binary_function` on request from libc++), Gaudi (a
  missing include; libraries found from python without `DYLD_LIBRARY_PATH`), ACTS (CBOR from
  `std::byte`, which libc++ cannot read through `char_traits`), Geant4 10.6 (`thread_local`
  with clang on arm64; a missing include; no fat LTO objects), GeoModel and chai (tests'
  library suffixes). GNU-only shell (`sed -i`, `paste` without `-`) is gone from the scripts.
- athena-core (patches 0005, 0006): yampl, valgrind and bfd optional; Valkyrie left out
  (`packages_excluded_osx.txt`); `<bit>` before classes that include a header inside their
  bodies; `std::invoke_result_t` for `result_of_t`; `fenv_t` on Apple silicon; `<malloc.h>`,
  `prctl`, `TEMP_FAILURE_RETRY`, `getservbyport_r`, `struct msgbuf`, `std::beta` (libc++ has
  no special functions); `std::vector<bool>`'s proxy handed to CORAL; libc++ helper templates
  matched by a dictionary's selection patterns; libc++'s `create_directories` returning false
  for a path ending with `/`; no `LD_PRELOAD` in `athena_preload.sh`; AtlasCMake's
  `.components` files from the library's real name (`.dylib` for shared libraries).
- athena-detdescr and athena-edm (patches 0001): `sincos` (a glibc extension; `CxxUtils::sincos`
  or a local shim), missing includes, `std::legendre` (a recurrence instead), `<malloc.h>`, an
  Apple-only branch of INav4MomAssocs that no longer compiles, byte order macros. TRT_GeoModel's
  private copy of GeoModel's `ArrayFunction` broke GeoModel's persistifier on macOS: two
  classes with one name, so the `dynamic_cast` there failed on the copy's RTTI.
- FPEs on macOS that are not Athena's: the edm T/P converter tests of the tau EDM (20.1.7.2,
  20.7.2.2) reported FPE INVALID in every event. Bisected (FE_INVALID checks around the
  dumper's python functions, then inside the converter): `xAODTauJetAuxContainerCnv_v2` takes
  `DeltaR` with the HLT taus' intermediate axis, a null vector, and conda-forge's macOS
  libPhysics computes `fZ/ptot` before testing `ptot == 0` (`fdiv` then `fcsel`): 0/0. ROOT is
  built with gcc on Linux, which does not speculate trapping operations. Apple silicon cannot
  trap FPEs, so there is no stack trace; lldb needs developer mode. The tests check the logs for
  FPE warnings only on Linux.
- athena-edm-det on macOS (patch 0001): `sincos`, unqualified `resetiosflags` (found by ADL
  only through libstdc++'s enum `fmtflags`), a vector iterator made from 0. Its POOL test then
  failed to read the mc23 HITS file: ROOT's `TTreeIndex` reported a duplicate key and the
  second event's EventInfo was not found. The file's `index_ref` values are 0x210889 << 32 plus
  the entry, beyond 2^53; ROOT 6.40.02 picks between the `Long64_t` key and its `long double`
  range-checked one with a ternary, so even `BuildIndex(name, true)` (APR's call) converts the
  key to `long double`, a `double` on Apple silicon (80 or 128 bits on Linux). 6.40.04 casts
  it; conda-forge has it, and a test with it indexes the file without duplicates. osx-arm64
  now uses root_base 6.40.4 (a selector in every `variants.yaml`); the ROOT-based externals
  (tdaq-dqm-core, lcg-cool, Gaudi, ACTS) and layers are rebuilt against it.
- macOS rootmaps name `libRootUtils.so` (AtlasCMake uses the module suffix for reflex
  dictionaries and links only dictionary libraries to it): the layers' build scripts link
  every missing `.so` a rootmap names to the `.dylib`.
- With ROOT 6.40.04 the edm-det POOL test read the HITS file, then failed to write the mc23
  RDO: `PixelRDO_ContainerCnv` reported "Converter not implemented for this concrete type",
  as `dynamic_cast<const Pixel1RawData*>` failed. `Pixel1RawData` is `final` and all its
  virtual functions are inline, so it has no key function: every library that uses it has a
  copy of its vtable, and ld64 makes each copy private (`weak_def_can_be_hidden`; `nm -m`
  shows them "non-external (was a private external)"). Clang turns a `dynamic_cast` to a final
  class into a comparison with the vtable's address (since clang 17), which then fails for an
  object made in another library. Linux's dynamic linker merges the copies. A two-library
  test reproduces it, and `-fno-assume-unique-vtables` (the run-time `dynamic_cast` instead)
  fixes it: athena-externals' `conda-postconfig.cmake` adds it for C++ on macOS (so every
  layer has it) and Gaudi's recipe too. athena-externals, Gaudi and the layers are rebuilt.
  With it the POOL test reads, writes and reads back the HITS, RDO and ESD files. One T/P
  converter test (TrackParticleTPCnv_16.6.3) then differs from ATLAS's reference in one number
  of 137,867 lines, in its last digit: the mass of a 360 GeV pion, computed from its energy and
  momentum, where macOS's libm rounds differently from glibc's. On macOS a reference diff
  whose numbers all agree to one unit in their last printed digit is accepted
  (`test/lastdigit_diff.py`); Linux still compares exactly.
- linux-64: edm-det, analysis and reco-tracking reproduce ATLAS's x86_64 references exactly.
  The reco dumps do not: of 1.7 million ESD lines 12 differ, and 2 of the AOD's, by one unit
  in the last printed digit (calorimeter cluster cell weights, two MET `sumet`s) or by the
  sign of a zero (tau `mCombined`/`mPanTauCellBased`). On aarch64 the same recipe reproduces
  ATLAS's release, and ATLAS's flags (`-O2`) and conda-forge's (`-march=nocona
  -mtune=haswell -ftree-vectorize`) should not change IEEE results on x86_64, so presumably a
  library compiled differently there (ROOT, Eigen, ...) or Rosetta; finding out would take
  several emulated rebuilds. The dumps are not shipped (their input's licence is unclear), so
  no tolerance can be applied: `reco_dumps.linux-64.sha256` lists both ATLAS's sums and this
  build's, with a comment, and the test accepts either. (Unverified on real x86_64 hardware,
  e.g. conda-forge's CI, which may match ATLAS's.)
- macOS athena-analysis (patch 0002): missing standard includes, glibc's `ulong` and
  `HOST_NAME_MAX`, `sincos`, TrigConfIO's `-lstdc++fs` (Linux only now), a header that needs
  `<string>` before core's `ConcurrentStrMap.h`, and `std::flat_set`, which libc++ 20 does not
  have: TrigGlobalEfficiencyCorrection takes Boost's `flat_set` there (`__has_include`). One of
  its headers has CRLF line endings: `_work/mkpatch.py` keeps them now. L1TopoAlgorithms
  downloads two networks at build time (ADVAE2A, ARTEMIS2A) whose hls4ml `ap_types` declare
  `template<typename _Tp> class complex;` in `std`, a second `std::complex` next to libc++'s
  `std::__1::complex`: on macOS `build.sh` passes ATLAS's `ATLAS_<name>_PATCH` hook a patch
  (`hls4ml-ap_types-libc++.patch`) that includes `<complex>` instead. macOS's C library has
  no `quick_exit`, which AthViews' unit test calls to skip finalization: `_Exit` there (several
  sim/reco tests call it too, but none of the tested packages).
- The layers' unit tests (edm-det, analysis: `unit_tests.txt`) did not run from the start of
  M8: the `-` that BSD `paste` needs came with `<<` instead of `<<<`, a here-document with an
  empty body, so ctest's label regex was `^()$` ("No tests were found!!!", not an error).
  Fixed; the edm-det and analysis packages built before (linux-64, macOS edm-det) are to be
  rebuilt to run them.
- ATLAS's scripts start with `#!/usr/bin/bash` (233 in the sources, 51 installed in `bin/`,
  e.g. core's `noerror.sh`, which ATLAS's ctest wrapper runs after every test) or
  `#!/bin/env python`: macOS has neither path, and every unit test failed there. The layers'
  `build.sh` rewrite them to `#!/usr/bin/env ...` in the sources before configuring (some
  tests run scripts from the sources), on every platform.
- The macOS unit tests of athena-analysis (77, all pass now) needed more:
  - SIP drops `DYLD_LIBRARY_PATH` from the many tests that are python scripts
    (`#!/usr/bin/env python`), and the build area's libraries carry only the install rpaths:
    Gaudi's plugin loader finds a component library by its full path, but not the layer's
    libraries it links. The layers now install before running their tests (the first rpath
    is the layer's own install area).
  - ATLAS's `post.sh` (log comparison with references) needs GNU sed (comments after sed
    commands) and GNU diff (`-E`), and HDF5Utils' test GNU grep (`-P`): athena-core requires
    conda-forge's `sed`, `diffutils` and `grep` on macOS.
  - With libc++, `std::map` makes AtlasSTLAddReflexDict's rootmap list the `pair<>`s of some
    maps (`pair<string,vector<int> >`) that xAODCoreSTLDict lists too; ROOT warns about each
    such duplicate in every job (not for STL containers, so Linux's 41 duplicates are
    silent), and the warnings broke 7 reference comparisons. The layers' rootmaps keep only the
    first entry of each class on macOS, which is the one ROOT uses anyway.
  - SelectionHelpers' expression `Lexer` holds a `std::string` and a `boost::tokenizer` with
    iterators into it, and is moved with the defaulted move constructor: the iterators then
    point into the moved-from object, destroyed right after (undefined behaviour everywhere).
    With libstdc++ (15-character SSO) the 20-character test expression is on the heap and
    survives; libc++ keeps up to 22 characters inline. Patch 0003 keeps the string on the heap
    (to be reported to ATLAS).
  - L1TopoSimulationUtils' reference has libstdc++'s text of an `out_of_range`: excluded on
    macOS (`unit_tests_excluded_osx.txt`, read by the layers' `build.sh`).
- With the here-string fixed, athena-edm-det's 364 unit tests run: all pass on linux-64; on
  macOS 2 of CaloTPCnv fail, whose references list cells in the order `std::shuffle` gave
  them (the standard leaves its algorithm to the implementation, and libc++ shuffles the same
  seed differently): excluded on macOS like L1Topo's.
- athena-analysis's recipe test on macOS (ATLAS's MC DAOD_PHYS test): the CP algorithms'
  pileup block declares the `eventNumber` branch as `unsigned_long`, but `EventInfo`'s is a
  `uint64_t`, which is `unsigned long long` on macOS: `SG::ExcAuxTypeMismatch`. Patch 0002
  declares it `uint64` (the same type on Linux, so Linux's packages need no rebuild). With
  it, the Open Data analysis, the full-simulation test (149 entries, 5130 branches, as on
  Linux) and the PHYSLITE one run on macOS (no references there to compare with).
- athena-reco-tracking on macOS: 26 compile and link errors (`ninja -k 0` on the failed tree
  lists them all), fixed by its new patch 0001: `<flat_set>` (Boost's), `std::random_shuffle`
  (gone since C++17: `std::shuffle`; SiGNNTrackFinderTool sorts the edges right after, and
  had made an unused `mt19937` for it), glibc's `sincos()` and `<sys/sysinfo.h>`, GNU's
  `<ext/functional>` (unused), iterators initialised with `0` (libc++'s have no constructor
  from a pointer), `pow()` of a Gaudi property (ambiguous), JiveXML's `__APPLE__` branches,
  which are for Apple's RPC headers (conda-forge's macOS build uses libtirpc as Linux does;
  `HAVE_STRUCT_RPCENT` keeps libtirpc's `rpcent` from clashing with `<netdb.h>`, and
  `strerror_r` is POSIX's there), and TrkAlgebraUtils, which links gfortran's implicit
  libraries, static ones outside the search path on macOS (`emutls_w`): not there, as
  conda-forge's BLAS and LAPACK bring the runtime themselves. One error was in a header of the
  analysis layer (`TrackQualityCuts` copies maps with `const std::string` keys, which libc++
  assigns element by element): analysis patch 0002, so analysis was rebuilt on macOS. None of
  these changes Linux's results, so the linux-64 packages stand.
- With the laptop free overnight (2026-10-13), the builds used 10 threads (5 for macOS, 5 for
  the linux-64 container), back to 5 in all at 08:00 (`_work/morning.sh`).
  `_work/osx-chain2.sh` reads each recipe's `CPU_COUNT` from `_work/osx-work/cpu_count`.
- athena-rest on linux-64: the derivation dumps differ from ATLAS's x86_64 release in 39
  lines of DAOD_PHYS and 2 of DAOD_PHYSLITE. 30 by one unit in the last printed digit, 4 by one
  unit of a float (ECF3), and 7 electrons' `UEcorr_Pt` by up to 2.8 GeV: there this build has
  exactly the values of ATLAS's aarch64 release, whose x86_64 and aarch64 releases disagree on
  them (a quantity sensitive to the code path, not a problem of this build). The linux-64
  sha256 file lists this build's sums too, and `run_derivation.sh` accepts any sum listed for
  a dump, as reco's test does.
- athena-reco-tracking's recipe test passed on macOS, but its dump was 2% shorter than Linux's:
  the tracking had found 9 tracks where Linux finds 75, and no primary vertex. The test compares
  dumps only where ATLAS has a release, so nothing was checked there. Cause: the silicon seed
  maker (`SiSpacePointsSeedMaker_ATLxk`) got all 2627 space points, as on Linux, and made 0
  seeds (231 on Linux), because its radius-sorted lists held only 4 distinct space points, each
  about 390 times. The pool of `SiSpacePointForSeed`s is a `std::list` with ATLAS's
  `SG::ArenaPoolSTLAllocator`, and libc++'s `std::list` allocates each node through a temporary
  copy of the allocator (`__allocation_guard`), whose own pool (copies do not share it, by
  design) is freed with the copy: every node reused the same memory. Analysis patch 0002 makes
  these lists use `std::allocator` under libc++ (`SiSpacePointsSeedMakerEventData.h`; Linux's
  code is unchanged). It is the only `std::list` with that allocator in Athena. With it, a kept
  tree's three libraries that use the header, swapped into a test environment, reconstruct
  what Linux does: 894 seeds and 166 tracks, the dump's size and collections identical, 22
  lines of 419,547 differing in one track's TRT hits. The macOS stack is rebuilt from analysis
  (reco-tracking and trigger use the header). Found by bisecting with counters in the seed
  maker, rebuilt in the kept tree (`ninja` on one library), with the installed library's rpaths
  (`install_name_tool`), and swapped in by replacing the file (overwriting a signed library in
  place gets the process killed).
- So that such failures do not pass silently: the dump tests (edm-det, reco-tracking, reco,
  rest) also compare each collection's size (its lines in the dump, over all events) with
  ATLAS's release, within 5% (`dump_counts.py`, `<name>_dump_sizes.txt` from ATLAS's x86_64
  release; its aarch64 release has the same sizes), on every platform. The broken macOS
  tracking dump fails it (track particles 924 lines instead of 9828, no forward or large-d0
  tracks, half the vertex lines).
- Rebuilt with the fix (CPU_COUNT=2): analysis passes again (77 unit tests, 6642 s), and
  reco-tracking passes with the full output: 419,547 lines, all 9 collections' sizes as in
  ATLAS's release (6057 s).
- reco on macOS: 16 files did not compile or link (reco patch 0002, README lists them). Found
  in one pass with `ninja -k 0` in the failed tree (`_work/osx-work/k0.sh`), fixed there until
  the whole layer built. A scan of trigger, sim and rest for the patterns already fixed below
  (`sincos`, `HOST_NAME_MAX`, `finite`, special functions, `ulong`, `<ext/...>`) gave their
  patches (trigger 0001, sim 0001) before they are built. Notable:
  - CMake's `file(GLOB)` ignores case on macOS: `util/[!make]*.cxx` (MuonVertexValidation)
    left out `MSVtxPlotMaker.cxx`, and the executables did not link.
  - CLHEP is built without `-fvisibility-inlines-hidden` so that GenericFunctions' inline
    `clone()`s are exported, but on macOS ld64 hides them anyway: clang marks inline functions
    `weak_def_can_be_hidden`, and the linker makes them private. A call through the base class
    (virtual) needs no symbol; GeoXPEngine's direct calls on temporaries did.
  - `DataVector::insert(pos, move_iterator, move_iterator)` wraps the iterators in
    `CxxUtils::releasing_iterator`, which has `!=` but not `==`; libc++'s `vector::insert`
    for input iterators uses `==`. Fixed at the four call sites (under `_LIBCPP_VERSION`) rather
    than in CxxUtils, which is athena-core and would mean rebuilding every layer.
- reco's Reco_tf test then aborted on macOS after 10 minutes: "no dictionary for class
  LArMinBiasAverageP" while reading the LAr conditions. LArRawConditions' selection files
  (edm layer) leave 27 classes commented out, "picked up through iterator pattern below":
  `<class pattern="__gnu_cxx::__normal_iterator<const X*"/>`. With libstdc++ the iterator's
  second template argument, `std::vector<X>`, makes genreflex add `X`; libc++'s
  `std::__wrap_iter<const X*>` has only the pointer (checked with genreflex on a toy header:
  a `__wrap_iter` pattern selects the iterator and not `X`). edm patch 0002 selects the 27
  classes by name. Only a dictionary library changes, which no other layer's build uses, so
  locally edm is rebuilt and edm-det, analysis and reco-tracking are not.
- Builds with all 10 cores overnight: memory is logged every 30 s (`_work/osx-work/memlog.sh`,
  `logs/mem.log`); the recipe builds use 8 jobs (reco's compiles take up to 3 GB each).
- reco then built (9134 s with its test), but Reco_tf crashed on the first event in
  `GSFUtils::findMerges` (egamma's GSF refit). The stack trace showed the return address after
  a call to `aligned_alloc` (a leaf function: frame-pointer walks skip it): `AlignedDynArray`
  asks for `n * sizeof(T)` bytes at 32-byte alignment, and macOS's `aligned_alloc(32, 12)`
  returns null where glibc's does not. reco-tracking patch 0001 rounds the size up; the
  other `aligned_alloc` calls in Athena already do. After the crash, the job hung in
  CoreDumpSvc for the hour of TimeoutAlg's event timeout before it exited.
- reco passes on macOS (4421 s with reco-tracking's fix): Reco_tf's ESD and AOD dumps (1.7M
  and 406k lines) have the sizes of ATLAS's release in all 175 and 97 collections.
- trigger on macOS: 14 files did not compile or link, beyond what the scan had found (trigger
  patch 0001). Besides missing includes (`<algorithm>`, `<iomanip>`, `<iterator>`, `<map>`,
  which libstdc++'s headers bring in), `<ieee754.h>` and `std::experimental::filesystem`:
  - `uint64_t` is `unsigned long long` on macOS, so `boost::hash_combine(uint64_t&, ...)` does
    not match its `size_t&` seed, and `bitset::to_ulong()` is ambiguous between overloads for
    `uint32_t` and `uint64_t`.
  - libc++'s `ios_base::fmtflags` is an integer, not an enum: an unqualified
    `setiosflags(std::ios::fixed)` is not found by argument-dependent lookup.
  - libc++'s map copy assignment reuses the nodes and assigns the values; a mapped
    `pair<const X, ...>` cannot be assigned (TGCDatabaseManager): copy, then move.
- trigger then built, but runHLT stopped generating the L1 menu: `L1TopoAlgConfig` has no
  `eEmNoSort`. The module is written at build time (analysis layer) by
  `TrigConfL1TopoGenPyAlg`, which lists the algorithms that `libL1TopoAlgorithms` registers in
  its static initialisers; on macOS the program did not link that library, and the module came
  out empty. conda-forge's macOS LDFLAGS have `-dead_strip_dylibs` (GNU ld's `--as-needed`), and
  ATLAS's `atlas_disable_as_needed()`, which 20 packages call for such links (L1Topo, the
  generators, AtlasGeant4, ByteStreamStoragePlugins), removes only `--as-needed`. AtlasCMake's
  macro now removes both on macOS (athena-externals patch 0005). Redefining the macro in
  `conda-postconfig.cmake` does not work: each project's `Config.cmake` finds its base project
  (whose PostConfig defines it) before it includes `AtlasFunctions`, which defines ATLAS's macro
  again, and `atlas_project()` does the same before it reads the packages. A layer uses the
  AtlasCMake copy of the layer below, so the whole stack is rebuilt (detdescr included: a
  rebuild that skipped it carried its old copy into every layer above). With it the program
  links `libL1TopoAlgorithms` and the module has 706 lines.
- trigger then passed on macOS: the HLT with the Dev menu counts 111 chains, as ATLAS's release
  does (build and tests 69 min with 5 threads; reco 94 min).
- sim on macOS: FastCaloSim constructs a vector iterator from a pointer (libc++'s is a class
  with a private constructor from it), and AtlasGeant4 links with `-Wl,--exclude-libs,ALL`,
  which Apple's linker does not know (sim patch 0001). sim then passed: `Sim_tf.py` with
  FullG4MT_QS, the hit collections within the tolerances as on Linux (36 min with 5 threads).
  rest asked for `libgl-devel` and `libglu`, which conda-forge has only for Linux: OpenGL is a
  system framework on macOS.
- rest on macOS (rest patch 0002): `<span>`, `<charconv>` and `mkstemps`' `<unistd.h>` that
  libstdc++ and glibc bring in implicitly, `std::views::chunk` (not in libc++ 20: PileUpMT
  iterates over spans), a `std::vector` of C arrays (LArSamplesMon), and `vector::assign` from
  `CaloClusterCellLink`'s iterator, which libc++'s `assign` does not take (CaloD3PDMaker).
  VP1's 14 system libraries link "GL" by name, which names nothing on macOS, and FindOpenGL
  (CMake 4) takes XQuartz's `/usr/X11R6/lib/libGL.dylib` before the framework where XQuartz is
  installed (this Mac, not conda-forge's CI), with conda-forge's `CMAKE_FIND_FRAMEWORK=LAST`.
  athena-externals' `conda-postconfig.cmake` defines a `GL` target for the OpenGL framework and
  ignores the XQuartz prefixes on macOS.
- rest then built, but its derivation stopped in initialize: "unable to dcast AlgTool
  DiTauOnnxDiscriminantTool to interface DiTauOnnxDiscriminantTool". DiTauRec compiles its
  sources into both its component and DiTauRecLib, so the tool class (with its type_info) is in
  both. ELF's symbol interposition makes the two one on Linux; on macOS each library keeps its
  own, the component makes the tool, and DerivationFrameworkTau's `ToolHandle` of the concrete
  class casts with DiTauRecLib's. 15 packages compile sources into both; in three, another
  package holds a `ToolHandle`, `ServiceHandle` or `dynamic_cast` of such a class (a scan of
  the CMakeLists and of the sources): DiTauRec, HGTD_Calibration and
  ActsVertexReconstruction (the last two Run 4 only). Their components are now built from
  `src/components/` only and link the library (reco-tracking patch 0002, reco patch 0003;
  **upstreamable**). Only those component libraries change, so trigger and sim are not rebuilt.
- rest's derivation then ran events, and stopped in the PHYS skimming: "MultipleProxyLoader:
  unable to find valid proxy loader for TauJets.nTracks". ExpressionEvaluation's
  `MethodAccessorFactory` keys its accessors on ROOT's name for a method's return type and
  registers the `<cstdint>` types only. `TauJet::nTracks()` returns `size_t`, which ROOT names
  `unsigned long`; on Linux that is `uint64_t`, on macOS `uint64_t` is `unsigned long long`
  (`ULong64_t`). Analysis patch 0004 also registers `(unsigned) long` and `(unsigned) long long`
  (the map keeps the first of duplicate keys, so nothing changes on Linux), and the same for
  the aux-variable accessors (`unsigned long long`, `long long`). Only the ExpressionEvaluation
  library changes.
- athena-devel on macOS, tried in rest's test environment (with the dev packages and clang 20
  added) with the recipe's devloop test, before the stack's rebuild:
  - conda-forge has no `cxx-compiler` for clang 20 (1.10 is 18, 1.11 is 19, 2.0 is 21), and
    `atlas-rivet` ran-required `cxx-compiler`: every environment with Athena got clang 18, and
    clang 20 removed athena-sim and athena-rest. atlas-rivet now requires the compiler it was
    built with (`${cxx_compiler}_${target_platform} ${cxx_compiler_version}.*`); athena-devel
    takes `${c_compiler}`/`${cxx_compiler}` the same way, and `macosx_deployment_target` 13.3
    (its activation sets `MACOSX_DEPLOYMENT_TARGET`).
  - The work area's CMake took Homebrew's Python 3.14 framework (`/opt/homebrew` is in CMake's
    system prefixes, and frameworks come first without conda-forge's `CMAKE_ARGS`), and its
    python byte-compilation failed. `conda-postconfig.cmake` sets `CMAKE_FIND_FRAMEWORK`,
    `CMAKE_FIND_APPBUNDLE` and `Python_FIND_FRAMEWORK` to LAST unless given, and ignores
    `/opt/homebrew` and `/usr/local`.
  - The work area's libraries had no rpaths to the layers: AtlasCMake (patch 0005) sets them only
    from `CMAKE_INSTALL_RPATH`, which the layers' builds pass. `conda-postconfig.cmake` defaults
    it, for a project that does not give it, to its own `<platform>/lib` (first, so that what a
    work area rebuilds takes precedence), every installed layer's lib/ and the prefix's lib/.
  - Then conda-forge's bash crashed (SIGSEGV) on `source build/*/setup.sh`, on any glob in fact,
    with the layers set up: their `env_setup.sh` (AtlasLCG's `lcg_generate_env`) put the
    externals' library directories, i.e. the prefix's lib/ (and, from one external, the build
    machine's SDK `System/Library/Frameworks`), in `DYLD_LIBRARY_PATH`. dyld then loads the
    prefix's libiconv, libsqlite3, libcompression, ... for the system's in every process that
    keeps the variable (not SIP-protected binaries such as conda's bash and python). The rpaths
    cover the externals, so athena-externals patch 0006 writes no `DYLD_LIBRARY_PATH` there. It
    is in AtlasLCG, which every layer copies, so the macOS stack is rebuilt (overnight, 8 jobs).
  - With these (the `env_setup.sh` files edited by hand), the devloop passed: the work area
    built and `athena.py` printed the changed HelloWorld message.
- The macOS stack rebuilt overnight with all of this (8 jobs, 18:09 to 00:57: externals,
  atlas-rivet and the eleven layers): every layer passed its tests, rest's derivation
  included (DAOD_PHYS and DAOD_PHYSLITE with the collections of ATLAS's release; no macOS
  references, so compared in size only), and the `athena` metapackage's HelloWorld.
- athena-devel's test then failed in the work area's first compilation: `<complex>` saw no
  `INFINITY` or `NAN`. Outside rattler-build's `CMAKE_ARGS`, CMake takes Xcode's SDK (here
  macOS 27's), not the 11.0 SDK the layers build with. That `math.h`, in C++20 and later
  (`__has_feature(modules)` is true there), leaves both macros to the compiler's `float.h`,
  asking with `__need_infinity_nan`, which clang's `float.h` handles from version 21 on; clang
  20's defines them only outside strict ANSI mode (C23 or GNU modes), and ATLAS compiles with
  `-std=c++23`. `conda-postconfig.cmake` defines `INFINITY` and `NAN` for C++ when the compiler
  is clang < 21 and the SDK's `math.h` mentions `__need_infinity_nan` (never for the layers'
  builds). With it the devloop passed in the failed test environment (macOS 27 SDK). This
  hits every C++20 build with conda-forge's clang 20 and a current SDK: to report to
  conda-forge.
- athena-externals and athena-devel rebuilt with it: athena-devel's test passes. **osx-arm64 is
  done**: every recipe builds and passes its tests.
- linux-64 rebuilt with all of it (`/work/chain6.sh` in athena-dev-amd64: every external and
  layer with its recipe tests, then the metapackage and athena-devel; 05:12 to 01:10 UTC under
  Rosetta, 5 to 10 jobs): everything passes. The layers' dumps match their linux-64 references
  (reco's ESD and AOD, rest's DAOD_PHYS and DAOD_PHYSLITE), so the macOS patches change nothing
  there; `athena` runs HelloWorld and athena-devel's work area builds and runs. **linux-64 is
  done.**

**To do**: rebuild the linux-aarch64 stack with the patches of the macOS work (they change
Linux code too); report the libc++, ROOT SDK, `cxx-compiler` and `float.h` issues to
conda-forge, and the upstreamable fixes to ATLAS.
