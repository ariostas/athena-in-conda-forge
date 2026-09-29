# Athena: size, package graph and a first layer proposal

Reference: **Athena 25.0.73**, `aarch64-el9-gcc15-opt`, built from `nightly/main/2026-09-23T2100`
(commit `8c1c4b757d2`), gcc 15.2, on CVMFS at
`/cvmfs/atlas.cern.ch/repo/sw/software/25.0/Athena/25.0.73/InstallArea/aarch64-el9-gcc15-opt`.
All numbers come from the scripts in `athena-notes/analysis/scripts/` (python3 stdlib only).
They cache everything they read from CVMFS in `_work/`. See "Reproducing" at the end.

**Method.** `cmakeparse.py` is a small evaluator for the CMake subset used by the 1966 package
`CMakeLists.txt`:
- `if/elseif/else` over the project flags, `set`, `list`, `file(GLOB)`, `foreach`, `return`
  and `find_package`;
- every `atlas_add_*` call, with its source globs expanded against the real `src/` tree;
- evaluated in **Athena mode**: `XAOD_STANDALONE`, `XAOD_ANALYSIS`, `SIMULATIONBASE` and
  `GENERATIONBASE` all off, and CUDA/HIP/SYCL compilers absent, as on conda-forge CI.

**Validation.** The evaluator reproduces the release's exported targets
(`cmake/AthenaConfig-targets.cmake`, 2532 targets):
- **20 exported targets are missed.** 10 need CUDA (off on purpose). The other 10 are
  2 VP1 Qt plugins and 8 executables made by package-local helper functions that the parser
  does not run.
- **7 extra targets are parsed.** `Epos4_i`/`Epos4_iLib` are not built on aarch64, and 3 are
  `foreach` artefacts.
- ROOT dictionaries are MODULEs that are not exported, so they are compared separately.

There is no `compile_commands.json` in the install area. `objects-Release/` (648 MB) holds only
the 104 OBJECT libraries (Geant4 sensitive detectors etc., kept so AtlasGeant4 can be relinked).
TU counts are therefore "files matched by the source globs of targets that are configured".

---

## 1. Size

### 1.1 Totals

| Quantity | Value |
|---|---|
| Packages (`packages.txt`) | **1966** in 29 top-level directories. 1731 compile code, 87 are header-only/INTERFACE, 130 are python/scripts/joboptions only, 18 contain only tests/data |
| `atlas_add_library` | 1168 (exported: 892 SHARED, 220 INTERFACE, 104 OBJECT) |
| `atlas_add_component` (Gaudi plugin MODULEs) | 1000. Plus 102 `atlas_add_poolcnv_library`, 45 `atlas_add_tpcnv_library`, 17 `atlas_add_sercnv_library` (1124 MODULE targets exported) |
| ROOT dictionaries | 460 `atlas_add_dictionary` (reflex), 19 `atlas_add_root_dictionary`, 39 `atlas_add_xaod_smart_pointer_dicts`. 483 `.pcm` files in `lib/` |
| Executables | 191 (`bin/` has 2215 files; the rest are python/shell scripts) |
| Tests | 1892 `atlas_add_test`: 1111 compiled (1275 TUs) and 781 script/python tests. Plus about 390 calls to package-local test wrappers |
| **Translation units, non-test** | **14,861** real sources (libraries 9,057 + poolcnv/tpcnv 514 + components 5,056 + executables 234) + **599 generated** (one per reflex/ROOT dictionary and per pool/ser converter library) = **15,460** |
| TUs incl. tests | 16,735 |
| `.cxx/.cpp/.cc/.c/.cu` files in `src/` | 17,059. About 920 are never compiled in this configuration: CUDA, standalone-only `util/`, disabled code |
| Installed `lib/` | **3.10 GB** in 2966 files: 2478 `.so` and 483 `.pcm`. The sampled `libAthenaKernel.so` carries only stub debug sections of a few hundred bytes, so sizes are essentially code. Largest: `libAtlasGeant4.so` 52 MB, `libDerivationFrameworkTools.so` 41 MB, `libAtlasGeant4Lib.so` 36 MB |
| Rest of the install | `src/` 329 MB (all sources and headers, used as the include path), `data/` 338 MB, `share/` 72 MB, `python/` 60 MB, `bin/` 53 MB, `XML/` 11 MB |
| Merged per-project files | `lib/Athena.components`, `Athena.confdb`, `Athena.confdb2` (20 MB), `Athena.rootmap`: **one file each for the whole project** |
| `atlas_depends_on_subdirs` | not used any more (0 calls). Dependencies are expressed only through `LINK_LIBRARIES` |

### 1.2 Per top-level directory

"TU build" includes generated TUs.

| subsystem | pkgs | libs | comps | dicts | exes | compiled tests | TU build | TU tests | lib MB |
|---|---|---|---|---|---|---|---|---|---|
| Trigger | 247 | 145 | 158 | 47 | 37 | 96 | 2797 | 129 | 517 |
| MuonSpectrometer | 239 | 129 | 146 | 26 | 15 | 131 | 1626 | 135 | 340 |
| InnerDetector | 198 | 99 | 146 | 25 | 14 | 98 | 1410 | 131 | 308 |
| PhysicsAnalysis | 179 | 118 | 112 | 60 | 46 | 52 | 1408 | 55 | 453 |
| Reconstruction | 125 | 74 | 66 | 41 | 10 | 10 | 1142 | 10 | 251 |
| Tracking | 169 | 100 | 83 | 31 | 5 | 69 | 997 | 79 | 186 |
| Event | 112 | 69 | 16 | 63 | 9 | 119 | 927 | 120 | 188 |
| LArCalorimeter | 73 | 45 | 32 | 24 | 5 | 58 | 834 | 58 | 141 |
| Control | 91 | 59 | 47 | 35 | 10 | 194 | 747 | 201 | 131 |
| Simulation | 104 | 65 | 28 | 5 | 1 | 20 | 675 | 43 | 150 |
| ForwardDetectors | 76 | 53 | 34 | 22 | 4 | 29 | 445 | 29 | 68 |
| Calorimeter | 37 | 22 | 18 | 17 | 6 | 47 | 394 | 51 | 65 |
| graphics (VP1) | 44 | 38 | 7 | 0 | 1 | 0 | 344 | 0 | 31 |
| TileCalorimeter | 42 | 26 | 18 | 11 | 0 | 40 | 338 | 40 | 62 |
| Generators | 45 | 25 | 28 | 6 | 3 | 11 | 296 | 11 | 52 |
| Database | 42 | 27 | 16 | 19 | 7 | 47 | 254 | 88 | 33 |
| DetectorDescription | 31 | 24 | 8 | 9 | 2 | 39 | 229 | 40 | 13 |
| DataQuality | 12 | 7 | 2 | 4 | 7 | 7 | 208 | 7 | 19 |
| TestBeam | 13 | 10 | 6 | 3 | 0 | 0 | 145 | 0 | 27 |
| HighGranularityTimingDetector | 24 | 11 | 14 | 4 | 2 | 18 | 85 | 21 | 21 |
| other 9 (LumiBlock, AtlasTest, HLT, AtlasGeometryCommon, MagneticField, Commission, Tools, AsgExternal, External) | 63 | 22 | 15 | 8 | 7 | 26 | 159 | 27 | 31 |
| **total** | **1966** | **1168** | **1000** | **460** | **191** | **1111** | **15,460** | **1275** | **3086** |

### 1.3 Relative weight of a TU

`heavy.py` follows `#include`s through Athena's own headers and records which external header
families each non-test TU reaches.

| External header family | Share of the 14,774 non-test TUs that reach it |
|---|---|
| Gaudi | 84 % |
| Boost | 76 % |
| ROOT | 63 % |
| **Eigen** | **42 %** (reco-tracking 75 %, reco 60 %) |
| CLHEP | 33 % |
| GeoModel | 32 % |
| CORAL/COOL | 10 % |
| HepMC3 | 10 % |
| tdaq | 4 % |
| Geant4 | 4 % |
| ACTS | 3.5 % |

- **Athena headers per TU:** on average a TU pulls 80–330 Athena headers, depending on the
  layer.
- **Heaviest packages:** trigger monitoring/analysis and egamma performance, at about 1000
  Athena headers per TU.
- **What this means for cost:** besides Eigen, the cost drivers are xAOD auxstore templates,
  Gaudi property machinery and the reflex dictionaries (the 460 generated dictionary TUs,
  concentrated in `Event/xAOD` and `Trigger/TrigEvent`).

## 2. Dependency graph

### 2.1 Structure

- **The library graph is a DAG, in effect.** There are exactly 2 target-level cycles, and each
  goes through an INTERFACE (header-only) library, which CMake allows:
  `ColumnarMetLib` (interface) ↔ `METUtilitiesLib`, and
  `L1CaloFEXToolInterfaces` (interface) ↔ `L1CaloFEXSimLib`.
  - At package level these are the only 2 cycles (2 packages each), whether counted over
    libraries or over all non-test targets.
  - Tests add 2 more small cycles: `TrigConfData`↔`TrigConfIO`, and
    `ColumnarTestFixtures`↔`ElectronEfficiencyCorrection`↔`ElectronPhotonFourMomentumCorrection`.
  - Each cycle has to stay inside one layer, which is trivial.
- **At subsystem level everything is one SCC, as in CMSSW.**
  - Top level: 24 of 29 directories form one strongly connected component via library links
    alone. Only AsgExternal, External, HLT, TestBeam and graphics are outside it.
    Via all targets it is 26.
  - Second level (537 groups): one SCC of 162 (libraries) or 196 (all targets).
  - Examples: `Control/AthViews` and `Control/AthenaMonitoring` link calorimeter and trigger
    code; `Event/xAOD/xAODTracking` links `Tracking/TrkEvent/TrkTrack`; `xAODCaloEvent`
    links `Calorimeter/CaloEvent`.
  - **Consequence: layers must be cut per package, not per subsystem.**
- **Python imports** (`packages.py.dot`, 5494 edges) form one SCC of 567 packages.
  - `AthenaConfiguration/AllConfigFlags.py` imports the flag modules of every subsystem.
  - It does so through `_addFlagsCategory(..., modName)`, which calls `moduleExists()` first.
    Missing packages are tolerated by design, which is how AthAnalysis and AthSimulation work.
  - Against the proposed layers: 107 of the 333 python import edges out of `core` point to
    later layers, 143 out of `sim`, 90 out of `analysis`.
  - These are runtime-only dependencies. They need testing, but they do not block builds.

### 2.2 Undeclared header includes: effectively none

Every target exports only its own package directory as include path. For example,
`Athena::AthenaKernel` has `INTERFACE_INCLUDE_DIRECTORIES = src/Control/AthenaKernel`.
So an include of a package outside the link closure does not compile.

`includes.py` scanned all compiled TUs and all headers, 84k cross-package include lines.
Includes of packages outside the transitive link closure (tests included):

| Where the include is | Count |
|---|---|
| In compiled TUs | 34 lines: 11 package pairs in 9 packages |
| In headers | 386 lines |

Every compiled-TU case checked is preprocessor-guarded:
- `#ifdef XAOD_STANDALONE` in dual-use code (AsgTools, AsgTesting, xAODJet, JetUtils,
  PileupReweighting → `xAODRootAccess`, `ReweightUtils`);
- `#ifdef MUONCOMBDEBUG` (MuonCombinedTestTools → TrkTruthData);
- CUDA (ISF_FastCaloSim → ISF_FastCaloGpu, AthCUDACore).

**Unlike CMSSW, the CMake link graph is a sound basis for layer closure.** No include-closure
pass is needed, only a check of the `XAOD_STANDALONE` branches if a standalone build is ever
done.

### 2.3 Externals

The table lists each external (or group), how many packages use it directly, and the first
proposed layer that needs it (layers in §4).

| External | Packages | First layer | Notes |
|---|---|---|---|
| Gaudi (from AthenaExternals) | 1242 | core | `GaudiKernel` alone appears 1736 times in link lists |
| ROOT | 517 | core | |
| CLHEP | 314 | core | |
| Boost | 152 | core | |
| TBB, UUID, nlohmann_json, Eigen, VDT, Python, SQLite, XRootD, Davix, CURL, yampl, gperftools, valgrind | – | core | |
| **CORAL** | 79 | **core** | `Database/PersistentDataModel` (in every closure) uses CoralBase |
| COOL | 25 | core | |
| CREST (`CrestApi`, `chai`) | 1 | core | used by IOVDbSvc |
| **tdaq-common** | 66 | **core** | through ByteStream{CnvSvc,Data}. By detdescr/edm at the latest: TRT_Cabling, MuonNSWCommonDecode, TrigT1Result |
| full `tdaq` | 1 | trigger | only `HLT/Event/ByteStreamEmonSvc` (online monitoring) |
| HepMC3 (via `AtlasHepMC`), HepPDT (`TruthUtils`) | – | core | pulled in by PileUp/EventInfo closures |
| **GeoModel** | 89 | detdescr | |
| **ACTS** | 46 | **detdescr** | Muon Phase-II R4 readout geometry, `ActsGeometry`, `ActsEvent`, `xAODAuxiliaryMeasurement`: ACTS is needed well before tracking |
| XercesC | – | detdescr | |
| FastJet (+contrib) | 20 | edm-det / analysis | |
| **onnxruntime, lwtnn** | 30 / 22 | analysis | |
| HDF5/HighFive | 5 | analysis | |
| LHAPDF | 7 | analysis | ReweightUtils, AsgAnalysisAlgorithms |
| **Triton client + gRPC + protobuf** | – | analysis | through `PhysicsAnalysis/JetTagging/FlavorTagInference`, a dependency of METUtilities, tauRecTools, egammaMVACalib, JetMomentTools, ... (§4.2) |
| **Geant4** | 79 | sim | all in the sim layer |
| MC generators (Pythia8, Herwig3/ThePEG, Sherpa, EvtGen, Photos, Tauola, Hijing, Starlight, CRMC, EPOS4, OpenLoops, MadGraph, SuperChic, ...) | 27 | sim | 19 generator packages, all leaves, about 100 TUs in total, mostly python-only `*Control` packages. Only **Pythia8** is structural: `Pythia8_i` ← `G4ExternalDecay` ← `AtlasGeant4` |
| AdePT, Celeritas | – | – | disabled (`*_FOUND` false in the release) |
| vecmem, traccc, detray, CUDA/HIP/SYCL | – | trigger/rest | GPU/EF-tracking only. About 10 CUDA targets are simply not configured without a CUDA compiler |
| Qt5, Coin3D, SoQt, OpenGL | 35 | rest | VP1 only |

## 3. The existing ATLAS projects as boundaries

Sources:
- **Filters:** `Projects/*/package_filters.txt`, fetched from gitlab at commit `8c1c4b757d2`
  into `_work/projects/`. The semantics are in AtlasCMake `atlas_is_package_selected`: rules
  are anchored regexes, the first match wins, and a package that matches no rule is selected.
- **Package lists:** `packages.txt` of the installed releases.

| Project | Release on CVMFS | Built from | Packages | Filter reproduces packages.txt | Mode flag | Own-mode build TUs | Athena-mode closure adds |
|---|---|---|---|---|---|---|---|
| DetCommon | 25.0.73 | same nightly as Athena (`8c1c4b757d2`) | 18 | exactly | (standalone TrigConf/L1Topo) | 333 | 26 pkgs |
| AnalysisBase | 25.2.112 | `nightly/main/2026-09-24` (`994be31cbde`, one day later) | 228 (12 not in Athena: EventLoop*, SampleHandler, SUSYTools, JetReclustering, ...) | exactly | `XAOD_STANDALONE` (no Gaudi) | 1977 + about 160 for the 12 extra packages | 154 pkgs / 1553 TUs |
| AthAnalysis | 25.2.112 | same | 344 (4 not in Athena) | exactly | `XAOD_ANALYSIS` | 2837 | 137 pkgs / 1348 TUs |
| AthGeneration | none since 23.6 | – | filter selects 222 | – | `GENERATIONBASE` | 1724 | 82 pkgs / 721 TUs |
| AthSimulation | 25.0.73 | same nightly as Athena | 375 | exactly | `SIMULATIONBASE` | 2705 | 120 pkgs / 1028 TUs |
| VP1Light | none | – | filter selects 80 | – | `BUILDVP1LIGHT` | 938 | 115 pkgs |
| Athena | 25.0.73 | – | 1966 | exactly | – | 15,460 | 0 |

### 3.1 Nesting

`DetCommon ⊂ Athena`.

**AnalysisBase ⊄ AthAnalysis ⊄ Athena.** In set terms:
- AnalysisBase has 12 packages not in AthAnalysis and 12 not in Athena (standalone-only:
  EventLoop, SampleHandler, ...);
- AthAnalysis has 128 not in AnalysisBase and 4 not in Athena;
- AthSimulation and AthGeneration overlap by only about 150 packages.

### 3.2 They are separate builds, not layers

The projects are **not layers of Athena**. Each is a separate build of overlapping packages with
a different compile-time flag, and some libraries lose dependencies (and sources) in those modes.

**In Athena mode, their package sets are not closed.** AthAnalysis's CP tools need, for example:
- `xAODTracking` → `TrkTrack`/`TrkParameters`, and from there GeoModel via `TrkDetElementBase`;
- `xAODCaloEvent` → `CaloEvent`;
- `InDetTrackSelectionTool` → Trk extrapolation interfaces;
- `TrigDecisionTool` → `TrigNavigation`.

So an "AthAnalysis layer" inside an Athena stack is 137 packages bigger than AthAnalysis. An
Athena-mode AthAnalysis and an `XAOD_ANALYSIS` AthAnalysis are different binaries under the same
library names.

### 3.3 Branch

All of these are cut from **main**:
- 25.0.x Athena, AthSimulation and DetCommon are one nightly;
- 25.2.x AnalysisBase and AthAnalysis are weekly main nightlies (25.2.112 is one day after
  25.0.73).

Filters at the 25.0.73 commit reproduce the 25.2.112 package lists exactly. A conda release of
Athena 25.0.N and AnalysisBase 25.2.M can therefore share recipes and patches, but they are
never the same commit.

### 3.4 AnalysisBase as a standalone product

**AnalysisBase built in its own mode needs no Gaudi, CORAL/COOL or tdaq.**
- **Externals:** ROOT, Boost, Eigen, FastJet(+contrib), onnxruntime, lwtnn, HDF5, LHAPDF,
  nlohmann_json, GTest/GMock, nanobind, libxml2, CURL, VDT, TBB, CLHEP, KLFitter.
- **Size:** about 2.1k TUs, one CI job.
- The two Gaudi/CORAL references my parser reports are inert. `xAODCnvInterfaces` is an
  interface target naming GaudiKernel, and `TrigConfData` has `find_package(CORAL QUIET)` but
  never links it.

## 4. Layers

### 4.1 How they were built

`layers.py` defines each layer by what it should deliver:
- **Seeds:** regexes on package paths, or `@Project` for an ATLAS project's package set.
  Test, example, validation and monitoring packages are never seeds.
- **Dropped seeds:** a seed is dropped if its closure would pull in a forbidden external group
  or package. It then goes to a later layer, and the script reports it.
- **Closure:** all transitive link dependencies of the kept seeds.
- **Absorb pass:** unassigned packages matching the layer's absorb regex are added once
  everything they need is available.
- **Remainder:** the last layer takes whatever is left.

**By construction, 0 build dependencies point to a later layer.**

Cost assumptions:
- **CMSSW measurement:** 7.6 CPU-s/TU (see `../cmssw-in-conda-forge/PLAN.md`).
- **ATLAS is probably heavier.** 42 % of TUs reach Eigen, reflex dictionaries are big, and
  there are xAOD templates. So both 8 and 15 CPU-s/TU are shown.
- **CI budget:** 6 h and 7 GB.
  - At 2 cores and 15 s/TU, about 2,400 build TUs fit in 5 h of compiling. At 4 cores, about
    4,800.
  - The 7 GB limit will probably cap parallelism at 2–3 for Eigen/ACTS-heavy layers. That is
    unverified.

### 4.2 The proposal

| layer | pkgs | TU | gen TU | test TU | CPU-h @8s | CPU-h @15s | wall h, 4 cores @15s | wall h, 2 cores @15s | Eigen % | ACTS % | G4 % | Athena hdrs/TU | lib MB | heavy externals (besides Gaudi/ROOT/Boost/CLHEP) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| core | 177 | 1108 | 94 | 397 | 2.7 | 5.0 | 1.3 | 2.5 | 0 | 0 | 0 | 96 | 151 | CORAL/COOL/CREST, HepMC3/HepPDT, tdaq-common |
| detdescr | 194 | 1511 | 57 | 114 | 3.5 | 6.5 | 1.6 | 3.3 | 46 | 4 | 0 | 89 | 151 | GeoModel, ACTS, CORAL/COOL, tdaq-common |
| edm | 166 | 1604 | 164 | 141 | 3.9 | 7.4 | 1.8 | 3.7 | 34 | 0 | 0 | 159 | 283 | ACTS, CORAL/COOL, tdaq-common |
| edm-det | 142 | 1388 | 129 | 316 | 3.4 | 6.3 | 1.6 | 3.2 | 33 | 4 | 0 | 157 | 152 | GeoModel, ACTS, FastJet, tdaq-common |
| analysis | 187 | 1658 | 91 | 68 | 3.9 | 7.3 | 1.8 | 3.6 | 43 | 0 | 0 | 332 | 466 | FastJet, onnxruntime/lwtnn, HDF5, LHAPDF, **Triton client/gRPC** |
| sim | 216 | 1411 | 13 | 59 | 3.2 | 5.9 | 1.5 | 3.0 | 27 | 3 | 40 | 189 | 241 | **Geant4**, GeoModel, ACTS, Pythia8 (+ optional generators), HepMC3, onnx |
| reco-tracking | 217 | 1183 | 4 | 83 | 2.6 | 4.9 | 1.2 | 2.5 | **75** | 5 | 0 | 315 | 346 | ACTS, onnx/lwtnn, tdaq-common |
| reco | 321 | 2142 | 14 | 25 | 4.8 | 9.0 | 2.2 | **4.5** | 60 | 11 | 0 | 338 | 619 | ACTS, FastJet, GeoModel, onnx/lwtnn |
| trigger | 182 | 1558 | 10 | 54 | 3.5 | 6.5 | 1.6 | 3.3 | 37 | 1 | 0 | 306 | 358 | tdaq-common (+ tdaq for 1 pkg), ACTS, onnx, (vecmem/traccc: GPU EF tracking) |
| rest | 164 | 1298 | 23 | 18 | 2.9 | 5.5 | 1.4 | 2.8 | 47 | 4 | 0 | 236 | 319 | Qt5/Coin3D/SoQt (VP1), Triton, GPU |
| **total** | 1966 | 14,861 | 599 | 1275 | 34 | 64 | | | | | | | 3086 | |

What each layer delivers:

1. **core** (Control, Database, Tools, AtlasTest, ByteStream, EventInfo, xAODCore/EventInfo/Metadata/CutFlow + AthenaPool).
   - Run `athena.py` with the Gaudi/Athena framework, StoreGate, ComponentAccumulator configuration,
     AthenaMP, PerfMon, POOL/RNTuple I/O, IOVDb/CREST conditions access and ByteStream I/O.
   - Write your own algorithms.
   - Left out and moved to later layers:
     - AthViews, AthenaMonitoring and DataModelTest link calorimeter, trigger and geometry code;
     - AthOnnx, AthTriton, AthDevice and AthCUDA need ML/GPU externals;
     - xAODEventInfoCnv → BeamSpotConditionsData → VxVertex → TrkSurfaces → GeoModel.
2. **detdescr**
   - Identifiers/IdDict and the GeoModel geometry of every subdetector, including GeoModelXml ITk.
   - Readout geometry, TrkDetDescr and ACTS tracking geometry, magnetic field, cablings, detector
     conditions data.
   - The closure also pulls in the core tracking EDM (TrkParameters, TrkTrack, ActsEvent,
     Muon R4 EDM), because readout geometry and Muon R4 depend on them.
   - Delivers: build and dump the ATLAS geometry, decode identifiers.
3. **edm**
   - xAOD, trigger EDM (TrigEvent, 477 TUs) and generic EDM, with T/P, AthenaPool converters and
     dictionaries.
   - Delivers: read and write AOD/DAOD in Athena and PyROOT.
   - `xAODTrackingCnv`/`xAODTrackingAthenaPool` cannot be here: they link MCTruthClassifier,
     ParticlesInConeTools and PFlowUtils. They land in *analysis*.
4. **edm-det**
   - Detector-level raw/prep/sim EDM and converters: Muon, ID, LAr, Tile, Forward, L1 RDOs
     (TrigT1 260 TUs).
   - Delivers: RDO/ESD/HITS I/O.
5. **analysis**
   - The AthAnalysis package set in Athena mode, with its Athena-mode closure: the Jet/MET/egamma/tau
     tool libraries, TrigDecisionTool, FlavorTagInference, InDetTrackSelectionTool.
   - Delivers: AthAnalysis-style CP tools on DAOD_PHYS/PHYSLITE.
6. **sim**
   - The AthSimulation and AthGeneration sets: G4Atlas, ISF/FastCaloSim, all sensitive detectors,
     the generator interfaces.
   - Delivers: `Sim_tf.py` EVNT→HITS. It needs all 79 Geant4 packages (632 TUs) and nothing
     else from later layers.
7. **reco-tracking**
   - ID/ITk data preparation, clustering, tracking (Trk, InDet, ACTS CPU), vertexing, HGTD,
     ID digitization.
   - It is the most Eigen-heavy layer (75 % of TUs reach Eigen).
8. **reco**
   - Muons (incl. Phase-II), calo (LAr/Tile/Calo reco), egamma, jets, MET, tau, PFlow,
     b-tagging, forward detectors, digitization/overlay for the other subdetectors,
     RecJobTransforms.
   - Delivers: `Digi_tf.py` and `Reco_tf.py`, without trigger.
9. **trigger**
   - L1 simulation, HLT algorithms/hypos/steering, the menu (`TriggerMenuMT`), EF tracking and
     trigger monitoring.
10. **rest**
    - DerivationFramework (`Derivation_tf.py`), D3PDMaker, DataQuality, VP1, TestBeam,
      GPU/Triton clients, remaining examples and tests.

**Layer-level dependencies.** The layers form a chain in practice, and each depends on nearly
all earlier ones:

| Layer | Also depends on (edges) | Main reason |
|---|---|---|
| sim | analysis (26) | TrkExInterfaces, MCTruthClassifier, TrigDecisionTool |
| reco-tracking | sim (46) | AthenaMonitoring and SiClusterizationTool are in the AthSimulation closure |
| reco | sim (156) | MuonRecToolInterfaces, AthenaMonitoring |

So they cannot be built as independent siblings on top of `edm`, except by moving those shared
tool/monitoring packages down.

**Tests.** Only 5 packages have tests that need a later layer:
- IOVDb/AthenaPool test packages in core/detdescr need edm;
- one edm test needs analysis.

### 4.3 Checks and caveats

- **Tests.** Test TUs (1275) are extra, and so is the time to *run* them. ATLAS tests are often
  athena jobs of minutes each, and core alone has 397 compiled test TUs and many script tests.
- **Heavy TUs.** Largest single-TU risks for the 7 GB limit:
  - the reflex dictionaries of big xAOD/Trig EDM packages (edm, 164 generated TUs);
  - `TrigEventAthenaPoolPoolCnv` (`lib` 14 MB);
  - ACTS-heavy tracking.
- **Geant4 LTO.** `AtlasGeant4` is built with LTO when available (`ATLAS_GEANT4_USE_LTO`), which
  makes its link step expensive (52 MB `.so`).
- **Moving the boundary.** The tdaq-common requirement can be pushed from core to detdescr by
  moving ByteStream out of core. CORAL cannot be avoided: it is in `PersistentDataModel`.

## 5. Implications for layering

1. **The split has to be per package and closure-driven, exactly as for CMSSW.**
   - Subsystems are one SCC at both directory levels, and the "obvious" boundaries do not hold:
     core framework packages link detector code, the xAOD EDM links legacy tracking EDM and
     GeoModel, readout geometry links tracking EDM.
   - The ATLAS projects are **not** closed in Athena mode.
   - `layers.py` gives 10 layers that are closed and all fit a 6 h / 4-core job at 15 CPU-s/TU.
     At 2 cores the worst is reco at about 4.5 h, before tests.
2. **The CMake link graph is trustworthy, so closure needs no include scan.**
   - It is effectively acyclic: 2 cycles, both through INTERFACE libs.
   - Per-target include paths leave no real undeclared includes.
   - This is much better than CMSSW, where includes.py had to add 26 packages to a layer.
3. **Merged per-project runtime files need per-layer equivalents.**
   - The build produces one `<Project>.components`, `.confdb`, `.confdb2` and `.rootmap`, the
     same shared-file problem CMSSW had with `.edmplugincache`.
   - ATLAS already supports several projects on one runtime path: `WorkDir` builds on top of
     `Athena`, and AthSimulation on top of its externals. If each layer is configured as its own
     ATLAS project (`atlas_project(<Layer> ... USE <PreviousLayer> ...)`), each gets its own
     merged files and the Gaudi plugin/confdb lookup should find all of them on
     `LD_LIBRARY_PATH`. `confdb2` merging across projects needs checking.
4. **Hard, early external requirements.**
   - Core already needs Gaudi (AthenaExternals' build), CORAL/COOL, CREST client, tdaq-common and
     HepMC3/HepPDT.
   - detdescr needs GeoModel and ACTS.
   - analysis needs onnxruntime, lwtnn, FastJet and the Triton client (through
     FlavorTagInference).
   - Geant4 is confined to `sim`.
   - Qt/Coin3D are confined to VP1 in `rest`.
   - The MC generator interfaces are leaves and can be dropped individually. Pythia8 is the
     exception, because AtlasGeant4 needs it.
5. **AnalysisBase is the cheapest standalone deliverable.**
   - It fits one job (about 2.1k TUs) with no Gaudi, CORAL or tdaq.
   - It is a separate, conflicting build: it is not a layer of Athena.
   - AthAnalysis in `XAOD_ANALYSIS` mode (2.8k TUs) is likewise a possible single-job product,
     and it conflicts with the Athena `analysis` layer.
   - Decide early whether conda offers "athena-*" layers, "analysisbase"/"athanalysis" products,
     or both. They would need mutually exclusive packages or separate prefixes.
6. **Python runtime dependencies cross layers freely**, but the flag system guards them with
   `moduleExists()`. A lower layer on its own should work, but that has to be verified with each
   layer's own tests.

## 6. Open questions

- **Real CPU-s/TU for Athena on gcc 15 and clang/libc++.** The table assumes 8–15 s. It should be
  measured on a sample (for example, core and reco-tracking) before fixing layer sizes. Also
  check peak RAM per TU for Eigen/ACTS-heavy packages and big dictionaries: does 7 GB allow
  `-j2`, `-j3` or `-j4`?
- **Does chaining ATLAS projects work in one conda prefix?** That is, `find_package(<PrevLayer>)`
  exported targets pointing into `$PREFIX`, per-layer `.components`/`.confdb2`/`.rootmap`, and
  `CMAKE_PREFIX_PATH`. This needs an experiment, like the one done for SCRAM in CMSSW.
- **AthenaExternals.** Gaudi (ATLAS fork/version), GeoModel, ACTS (ATLAS pins a version),
  CORAL/COOL, Geant4 (ATLAS configuration, possibly patched), onnxruntime, lwtnn, VecGeom and
  CheckerGccPlugins come from AthenaExternals, not LCG. Each must match conda-forge or become a
  recipe. This is the topic of the externals research.
- **tdaq-common.** It is needed from core (ByteStream) or at least detdescr. What is its
  licensing and buildability? Consider a "no-ByteStream" core variant.
- **Triton client / gRPC in analysis.** Can `FlavorTagInference` be built without Triton, or
  does it have to be patched?
- **CUDA targets.** About 10 are dropped without a CUDA compiler; confirm nothing CPU-side
  needs them. The release itself is built with CUDA 13.3.
- **The parser is not CMake.** Package-local `function`/`macro` bodies are not executed:
  8 executables from `_add_exec` and GeoComparison helpers, and roughly 390 wrapped tests.
  The Athena-mode evaluation is validated against the exported targets, but the
  AnalysisBase/AthAnalysis/AthSimulation "own-mode" numbers are not validated against those
  releases' exported targets. That is doable: their `cmake/*-targets.cmake` are on CVMFS.
- **Layer order and siblings.** Moving AthenaMonitoring, TrkExInterfaces, MuonRecToolInterfaces
  and a few tool-interface packages down, into edm or a small "interfaces" layer, might let sim
  and reco-tracking depend only on edm. That would allow them to be built in parallel and
  installed independently.
- **Data.** `data/` is 338 MB on its own. How much detector/conditions data (sqlite DBs,
  geometry DBs, `ATLAS_RELEASEDATA`, CVMFS calibration areas) does each layer need at runtime
  and in its tests? This is a separate analysis.

## Reproducing

```
python3 athena-notes/analysis/scripts/scan.py        # CVMFS -> _work/cmakelists.json, srcfiles.txt
python3 athena-notes/analysis/scripts/depgraph.py    # -> _work/pkgs.json, targets.json
python3 athena-notes/analysis/scripts/graph.py       # -> _work/graph.json; cycles, SCCs, externals
python3 athena-notes/analysis/scripts/stats.py --md  # size tables; -> _work/libmb.json (needs _work/lib_ls.txt)
python3 athena-notes/analysis/scripts/includes.py    # undeclared includes (reads ~40k files once)
python3 athena-notes/analysis/scripts/heavy.py       # heavy-header reach per TU
python3 athena-notes/analysis/scripts/projects.py    # ATLAS projects (needs _work/projects/*)
python3 athena-notes/analysis/scripts/layers.py      # layer table; --list L, --why PKG, --dropped L
python3 athena-notes/analysis/scripts/pyimports.py   # python import graph vs layers
```

`_work/lib_ls.txt` is `find lib -maxdepth 1 -printf '%s %y %P\n'` run in the install area.
`_work/projects/` holds `<Project>.package_filters.txt` and `CMakeLists.txt` from gitlab at
`8c1c4b757d2`, plus `packages.txt`/`packages.dot` copied from the CVMFS releases.
