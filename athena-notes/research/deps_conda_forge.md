# Athena 25.0.73 externals vs conda-forge

_Generated 2026-09-29 from these sources:_
- _the installed release on CVMFS: `/cvmfs/atlas.cern.ch/repo/sw/software/25.0/{Athena,AthenaExternals}/25.0.73/InstallArea/{x86_64,aarch64}-el9-gcc15-opt` (`packages.txt`, `ReleaseData`, `cmake/`, `lib/`, `src/`);_
- _the 1,966 package `CMakeLists.txt` files of the release, copied to `_work/athena-cmake/` and parsed for `find_package` (per-package users in `_work/find_package_users.json`);_
- _`atlasexternals` tag **2.1.91** (= the `nightly release:83c62584` recorded in AthenaExternals' `ReleaseData`), cloned in `_work/atlasexternals`;_
- _ATLAS Gaudi (`_work/Gaudi-atlas.git`) and ATLAS CLHEP (`_work/CLHEP-atlas.git`), both blobless clones;_
- _`LCG_110_ATLAS_5` `LCG_{externals,generators}_*.txt` (copied to `_work/lcg/`);_
- _tdaq-common 14-00-00 on CVMFS (`/cvmfs/atlas.cern.ch/repo/sw/tdaq/tdaq-common/tdaq-common-14-00-00`);_
- _conda-forge `repodata.json` for linux-64 / linux-aarch64 / osx-arm64 / noarch, downloaded 2026-09-29 (`_work/repodata/`, index + query helpers `q.py`, `rec.py`);_
- _`conda-forge-pinning` `conda_build_config.yaml` from main (`_work/cf_pinning.yaml`);_
- _the gaudi, acts and geomodel feedstock recipes;_
- _open conda-forge/staged-recipes PRs (`gh search prs`)._

_Platform shorthand: `l64` = linux-64, `la64` = linux-aarch64, `oa64` = osx-arm64 (osx-64 is not a target). "all 3" means the package exists on all three target platforms. **V** marks something checked directly (file, repodata, git), **G** a guess or inference._

## Summary

**Where Athena's externals come from (V).** Athena 25.0.73 is built on four layers:
1. **AthenaExternals 25.0.73** (the `atlasexternals` project, tag 2.1.91). It builds 31 packages, among them Gaudi, ACTS, GeoModel, Geant4, CLHEP, VecGeom, onnxruntime, lwtnn, Coin3D/SoQt and yampl.
2. **LCG_110_ATLAS_5**: ROOT, Boost, TBB, Python, Eigen, XRootD, all the generators, and about 150 Python packages.
3. **tdaq-common 14-00-00**: eformat, ers, EventStorage and dqm_core. It also bundles **CORAL, COOL, CrestApi and chai** as its "external" area.
4. **tdaq 14-00-00** (full online software), which exactly **one** package uses (`HLT/Event/ByteStreamEmonSvc`).

The release uses **126 distinct external `find_package` names** across its 1,966 packages, plus project-level ones (LCG, Gaudi, Acts, Qt5, GTest, Geant4, Boost, nlohmann_json, tdaq-common, CUDA/HIP).

**Coverage.** Of the roughly 50 externals the core needs (framework, reconstruction, conditions, I/O):
- about **38 are on conda-forge** in a usable version on all 3 platforms;
- **10 are missing**: CORAL, COOL, frontier_client, CrestApi, chai, tdaq-common, vecmem, yampl, boost-mpi3 and APTypes;
- the rest exist but with problems: Gaudi (Linux only), GeoModel (l64 only), ACTS (far too old, core only) and CLHEP (needs ATLAS patches).

**Generators and Python.**
- Generators are mostly missing. 8 of the roughly 25 generator externals Athena links are on conda-forge: pythia8, evtgen, photos, tauola(++), lhapdf, rivet, yoda, sherpa. contur is also there, but it is a runtime dependency only.
- Python runtime dependencies are nearly all on conda-forge. Only `histgrinder` is missing (Apache-2.0, trivial), plus the TDAQ online Python modules (not packageable).

**Missing core dependencies (new recipes needed):**
1. **tdaq-common** (14-00-00, Apache-2.0, all component repos public under `gitlab.cern.ch/atlas-tdaq-software/`):
   - Needed directly by 64 packages: every ByteStream converter, the HLT steering interfaces and DQ han. RAW-data reconstruction cannot be built without it.
   - Only a subset is needed: `ers`, `eformat`, `eformat_write`, `EventStorage` (DataReader/Writer, RawFileName), `compression`, `CTPfragment`, `hltinterface`, `MuCalDecode`, `circ`, `dqm_core`, `webdaq`, `EventStorageRecords`.
2. **CORAL** 3_3_20 and **COOL** 3_3_20 (upstream `lcgcoral`/`lcgcool`, CMake-built, not the CMS fork). 79 and 25 packages use them. **Neither has a LICENSE file (V).**
3. **frontier_client** 2.10.2: runtime backend of CORAL FrontierAccess. The CMSSW repo's `recipes/frontier-client` is **exactly this version** and can be reused unchanged.
4. **CrestApi** 6.2.12 (no LICENSE file, V) and **chai** 2.1.0 (Apache-2.0): the new CREST conditions access. Used by IOVDbSvc, CoralUtilities, TrigConfIO and CaloCondPhysAlgs.
5. **vecmem** 1.27.0 (MPL-2.0): the `AthDevice*` packages link it unconditionally, even without GPUs.
6. **yampl** 1.2: AthenaMPTools and AthenaServices (AthenaMP event service). **No LICENSE in the upstream repo `vitillo/yampl` (V).**
7. **boost-mpi3** v0.81 (header-only, ATLAS patch). `AthenaServices` does `find_package(bmpi3 REQUIRED)` and its config pulls `MPI::MPI_CXX` + Boost.serialization (V). **The core framework therefore needs an MPI (openmpi or mpich; both on conda-forge, all 3).**
8. **APTypes**: Xilinx ap_types commit 200a9ae + ATLAS patch, header-only, Apache-2.0. Only `GlobalSimulation` uses it. The CMSSW repo's `hls-arbitrary-precision-types` is a *different* (CMS) fork of the same headers. The two would collide on file paths.

**Hardest items:**
1. **Geant4.**
   - ATLAS uses **its own fork of Geant4 10.6.3** (`atlas-simulation-team/geant4` tag v10.6.3.15), built **static**, with VecGeom 1.1.21 USolids for cons/polycone.
   - conda-forge has 11.4.2 (and a stray 10.7.4 on la64 only).
   - Athena includes `G4AtlasRK4.hh` **unconditionally** (G4AtlasTools, Monopole). That header exists only in the ATLAS fork (10.6.3.x and 11.2.2.3 tags). It is not in upstream 11.4.2, nor in the fork's 11.3.2 tag (V).
   - Athena has `G4VERSION_NUMBER` guards for 11.x, so building against Geant4 11 is intended upstream (the ATLAS fork has 11.2.2.3), but it needs the fork's patches or an Athena patch.
2. **Gaudi.**
   - ATLAS's fork `v40r4.002` is upstream `v40r4` + **2 commits** (GMR1933/GMR1937: drop the use of ROOT's SSL API). It is not a deep fork (V).
   - conda-forge `gaudi` 40.4 and 40.6 exist, **but only on l64/la64**. The feedstock skips osx "due to lack of upstream support". **osx-arm64 has no Gaudi at all.** That is the main blocker for the osx-arm64 target.
3. **ACTS.**
   - ATLAS pins **v47.7.0** with the Json, GeoModel, Root and Fatras plugins, plus GNN/traccc/detray/covfie/actsvg when CUDA is available (it is in the nightly).
   - conda-forge `acts-core` is **45.5.1, core only** (depends only on boost), last built 2026-04.
   - ACTS breaks its API every major version and Athena follows atlasexternals exactly, so in practice this is a hard pin.
4. **tdaq / tdaq-common.** See above. tdaq-common is packageable. Full tdaq (CORBA/omniORB, IS/OH/emon) is not realistic, and it is needed by 1 C++ package plus ~15 online-only Python scripts, all of which can be dropped.
5. **CORAL/COOL/CrestApi licence status.** Same problem as CMSSW's CORAL: no licence files, so they cannot go to conda-forge until CERN clarifies.
6. **CLHEP.**
   - ATLAS uses `CLHEP_2_4_7_1_atl01` = 2.4.7.1 + 5 commits. Two are needed to compile Athena:
     - `RandBinomial` members `private`→`protected`, used by `AtlasCLHEP_RandomGenerators/RandBinomialFixedP` (V; still private in upstream 2.4.7.2);
     - Ziggurat generators without `thread_local`.
   - conda-forge has clhep 2.4.7.1 and 2.4.7.2, unpatched.
7. **The osx-arm64 gaps.** Missing on osx-arm64: gaudi, geomodel, thepeg, prmon, libunwind, valgrind, dsfmt, cuda, oracle-instant-client.

**Version / pinning comparison** (ATLAS 25.0.73 → conda-forge global pin → conda-forge latest):

| dep | ATLAS 25.0.73 | cf pin | cf latest (all 3 unless noted) | impact |
|---|---|---|---|---|
| ROOT | 6.40.02, **C++23**, builtin LLVM | root_base zip {6.36.10/20, 6.38.4/20, 6.38.4/23, **6.40.2/23**, 6.40.2/20} | 6.40.04; **6.40.02 cxx23 exists on all 3** | exact match possible |
| C++ std | 23 (gcc ≥15 or clang ≥22), else 20 | gcc 15 (linux), clang 21 (osx) | — | osx clang 21 → ATLAS default would be 20; force 23 to match ROOT cxx23 |
| Boost | 1.91.0 | 1.88 (gaudi/geant4 on cf built vs 1.90) | 1.92.0 | pick 1.90 (to reuse cf gaudi/geant4) |
| TBB | 2022.2.0 | 2023 | 2023.1.0 | same ABI (libtbb.so.12) |
| Python | 3.13.11 | 3.11–3.14 | 3.14 | 3.13 fine |
| numpy | 2.4.4 | 2 | 2.5 | fine |
| Gaudi | v40r4.002 (fork) | 40.4 | 40.6 (l64, la64 only) | linux builds of 40.4 exist for root 6.40.2/cxx23 (only with clhep 2.4.7.2) and root 6.40.4/cxx23 (with clhep 2.4.7.1 or 2.4.7.2), py313 |
| CLHEP | 2.4.7.1_atl01 | zip with geant4: 2.4.4.0/10.7.4, **2.4.7.1/11.3.2**, 2.4.7.2/11.4.2 | 2.4.7.2 | needs ATLAS patches |
| Geant4 | 10.6.3.atlas15 (static) | 10.7.4, 11.3.2, 11.4.2 | 11.4.2 | major gap, see above |
| VecGeom | 1.1.21 (+3 patches) | — | 2.0.0 | only for G4 USolids; drop or new series |
| ACTS | 47.7.0 | — | acts-core 45.5.1 (core only) | build own |
| GeoModel | 6.29.0 | — | 6.31.0 (**l64 only**; 6.29.0 exists) | feedstock needs la64/oa64; drags qt6/soqt6/geant4 |
| Eigen | 3.4.1 | — | 5.0.1 (3.4.0 available) | use 3.4.0 or test 5 |
| HepMC3 | 3.3.1 | 3.3 | 3.3.1 | match (Athena suppresses rootIO rootmap) |
| HepPDT | 2.06.01 | — | 2.06.01 | match |
| XercesC | 3.3.0 | 3.3 | 3.3.0 | match |
| XRootD | 6.1.1 | 6 | 6.1.1 | match |
| Davix | 0.8.10 | 0.8 | 0.8.10 | match |
| HDF5 | 1.14.6 | 1.14.6 | 2.2.0 | match pin |
| HighFive | 2.10.1 | — | 3.3.0 (2.10.1 available) | use 2.10.1 |
| fmt | 12.1.0 | 12.1 | 12.2.0 | match |
| protobuf / grpc | 7.34.1 / 1.78.1 | 7.35.1 / 1.82 | 7.36 / 1.83 | fine (Triton + FTag only) |
| nlohmann_json | 3.12.0 | — | 3.12.0 | match |
| onnxruntime | 1.26.0 (Microsoft binary tarball) | — | onnxruntime-cpp 1.30.0 (1.26.0 available, cpu + cuda variants) | use cf build |
| lwtnn | 2.14.1 | 2.14 | 2.14.2 | match |
| FastJet / fjcontrib | 3.5.1 / 1.102 | 3.5 / 1 | 3.5.1.5 / 1.104 | match |
| Qt5 | 5.15.15 | qt_main 5.15 | 5.15.15 | match (VP1 only) |
| Coin3D / SoQt / simage | coin 5297f6c (Coin 4.0.1 cmake) / soqt ea5cd76 (1.6.0a) / simage 2c958a6 | — | 4.0.10 / 1.6.3 (l64 also 1.6.0a) / 1.8.3 | fine (VP1 only) |
| libxml2 | 2.10.4 | 2.15 | 2.15.4 | API-compatible (G) |
| SQLite | 3.32.3 | 3 | 3.53 | fine |
| GSL / FFTW | 2.8 / 3.3.10 | 2.7 / 3 | 2.8 / 3.3.11 | fine |
| Pythia8 | 8.317 | 8.312 | 8.312 | needs bump (same as CMSSW) |
| LHAPDF | 6.5.5 | 6.5 | 6.5.6 | fine |
| Rivet / YODA | 4.1.2 / 2.1.2 | 4.1 / 2.1 | 4.1.4 / 2.1.4 | fine |
| compilers | gcc 15.2, cmake 4.4, CUDA 13.3 | gcc 15 / clang 21; CUDA 12.9/13.4 (linux) | — | gcc 15 matches exactly on linux |

**ATLAS patches that matter for compatibility** (V unless noted):
- **Change APIs that Athena uses (must be carried):**
  - CLHEP (RandBinomial protected, Ziggurat without thread_local);
  - Geant4 fork (G4AtlasRK4 stepper, G4WoodcockProcess (only in the optional AdePT/HepEm physics-list sources), G4GammaGeneralProcess access changes, Bertini fix, ATLASSIM bug fixes: 49 commits over upstream v10.6.3).
- **Build/compat only:**
  - Gaudi (2 commits, ROOT SSL API removal);
  - ROOT: atlasexternals has 9 cmake/vdt/clad patches, but these are only used when ATLAS builds ROOT itself (`ATLAS_BUILD_ROOT`). The LCG ROOT that Athena uses is the plain upstream tarball; no patch step in the LCG logs.
  - VecGeom (gcc15, clang, kConeTolerance); XRootD, Davix, TBB, BAT, Simage, boost-mpi3, APTypes (only when ATLAS builds them, except boost-mpi3 and APTypes, which ship).
- **ACTS, GeoModel, lwtnn, onnxruntime, prmon, CORAL, COOL, VecMem:** no ATLAS patches (V: empty `ATLAS_*_PATCH`/no `patches/`).
- **LCG generators with ATLAS patches:** the `*.atlasN` versions (photos++ 3.64.atlas1, tauola++ 1.1.9.atlas2, madgraph5amc 3.5.11.atlas16, SFGen 1.03.atlas2, epos4 4.0.3.atlas3, nlox 1.2.2.atlas9, hijing …atlas20260625, ggvvamp/qqvvamp .atlas1, mcfm 10.3.atlas). Patches live in `sft/lcgcmake` `generators/patches/` (e.g. `SFGen-1.03.atlas2.patch`, `epos4-4.0.3.atlas3.patch`); not inspected in detail.

**Already on staged-recipes (open PRs, 2026-09-29):**
- `herwig` (#33684, updated 2026-08-31);
- `gaudi` (#31883, stale: the feedstock exists anyway).
- Nothing for coral, cool, frontier, tdaq, eformat, vecmem, yampl, detray/traccc/covfie/actsvg, superchic, starlight, hijing, crmc, openloops, tauola, apfel, madgraph, pythia6, crest or histgrinder.

---

## 1. How Athena's externals are layered (V)

| layer | version | provides | built by |
|---|---|---|---|
| LCG_110_ATLAS_5 | gcc 15.2.0, el9, x86_64 + aarch64 (also el10/gcc16 variants) | ROOT, Boost, TBB, Python 3.13.11, Eigen, XercesC, XRootD, Davix, HepMC3, HepPDT, FastJet, HDF5, Qt5, CUDA 13.3.1, **all generators**, ~150 py packages, frontier_client, oracle 19.19, mysql, gdb, valgrind, … (290 externals + 50 generator entries on x86_64; aarch64 lacks hdf5_mpi, kokkos, protobuf2, epos4, mcfm, nlox, pepper_kokkos, compilebox (=Powheg)) | SFT lcgcmake |
| tdaq-common 14-00-00 | `TDAQ_RELEASE_BASE=/cvmfs/atlas.cern.ch/repo/sw/tdaq` | ers, eformat, EventStorage, compression, CTPfragment, hltinterface, MuCalDecode, circ, dqm_core, dqm_algorithm_helper, webdaq, HistogramStyles; **plus `installed/external/<platform>`: CORAL 3_3_20, COOL 3_3_20, CrestApi 6.2.12, chai 2.1.0** (built by `TDAQCExternal` via ExternalProject from gitlab) | cmake_tdaq, on top of LCG_110 |
| AthenaExternals 25.0.73 | atlasexternals 2.1.91 (`Projects/AthenaExternals/package_filters.txt`) | Acts, APTypes, boost-mpi3, CheckerGccPlugins, CLHEP, Coin3D, COOL*, CORAL*, flake8_atlas, **Gaudi**, GPerfTools (scripts only), Geant4, VecCore, VecGeom, GeoModel, GoogleTest, lwtnn, MKL (x86_64 only), onnxruntime, prmon, PyModules (pyami, histgrinder, lark, nanobind), Simage, SoQt, dSFMT, triSYCL, itksw-endec, hgtd-decoder, yampl, nlohmann_json, VecMem, Triton | ATLAS (ExternalProject per package) |
| Athena 25.0.73 | 1,966 packages | — | `Athena_BASE_PROJECTS AthenaExternals;25.0.73`; `PreConfig.cmake` also finds `LCG 110 EXACT` (postfix `_ATLAS_5`), `tdaq-common` (**"mainly to have packages find COOL/CORAL"**), and `TDAQ_VERSION 14-00-00`; `PostConfig.cmake` finds Gaudi |

\* `COOL`/`CORAL` are in AthenaExternals' `packages.txt`, but `ATLAS_BUILD_CORAL`/`ATLAS_BUILD_COOL` default OFF and no `liblcg_*` is in AthenaExternals' `lib/`. The libraries come from tdaq-common's external area.

Notes:
- **Gaudi is not a separate project any more.** It is built inside AthenaExternals: `External/Gaudi` downloads `atlas/Gaudi` v40r4.002 and installs into `include/Gaudi`, `lib/`, `python/`.
- **The GPU stack.** Both `x86_64` and `aarch64` nightlies are built with CUDA 13.3.1 (`ReleaseData cudapath`). As a result AthenaExternals also contains traccc 1.6.0, detray 0.111.0, actsvg 0.4.51, covfie, ModuleMapGraph, `libActsPluginGnn`, `libvecmem_cuda`, `libGaudiCUDA` and the Triton server/client.
- The aarch64 and x86_64 Athena `packages.txt` are identical.

## 2. What Athena actually uses: find_package census (V)

From the 1,966 package CMakeLists (number = packages calling `find_package(X)`; project-level finds excluded):

```
ROOT 518, CLHEP 314, Boost 153, GeoModel 89, CORAL 79, Geant4 79, tdaq-common 64, GTest 52,
Acts 46, nlohmann_json 37, Qt5 35, onnxruntime 30, Eigen 29, COOL 25, Coin3D 25, TBB 24,
lwtnn 22, FastJet 20, vecmem 14, GMock 11, Python 11, FastJetContrib 9, UUID 9, cx_Oracle 9,
traccc 9, GSL 8, Pythia8 8, Lhapdf 7, SoQt 7, VDT 7, HDF5 5, Oracle 5, requests 5, Rivet 4,
Threads 4, YODA 4, chai 4, AdePT 3, CUDAToolkit 3, OpenLoops 3, XercesC 3, hepmc3 3,
sqlalchemy 3, valgrind 3, Apfel 2, CURL 2, Celeritas 2, CrestApi 2, FFTW 2, HepPDT 2,
HighFive 2, LibXml2 2, OpenCL 2, OpenGL 2, OpenSSL 2, Photospp 2, Protobuf 2, SQLite3 2,
Tauolapp 2, TritonClient 2, TritonCommon 2, Xrootd 2, ZLIB 2, gRPC 2, hip 2, psutil 2,
pyyaml 2, stomppy 2, yampl 2, and 1 each: APTypes BLAS CppUnit Crmc Davix EPOS4 EXPAT EvtGen
Herwig3 Hijing Hto4l KLFitter LAPACK MadGraph Pepper Prophecy4f RPC Recola SFGen Sherpa
Starlight Superchic ThePEG XRT bmpi3 boto3 botocore chaplin cln contur dSFMT detray distro gdb
ggvvamp ginac glib gperftools graphviz ipython jmespath libffi libxkbcommon libzip lz4
matplotlib nanobind nlox numpy pandas pprof pygraphviz qqvvamp s3transfer sympy tdaq zipp
```

Components requested:
- **ROOT:** Core 497, Hist 322, RIO 300, Tree 296, MathCore 290, Graf 43, Physics 38, Gpad 36, Matrix 31, MathMore 17, GenVector 16, Minuit 14, Minuit2 10, TMVA 9, TreePlayer 9, HistPainter 8, ROOTTPython 7, Rint 6, **ROOTNTuple 5**, RooFit(Core) 4, EG 4, Net 3, XMLIO 3, ROOTDataFrame 2, XMLParser 2, Postscript 2, Geom 1, Graf3d 1, ROOTVecOps 1, ROOTNTupleUtil 1, CPyCppyy 1.
- **Boost:** unit_test_framework 51, thread 14, program_options 13, regex 6, timer 6, container 3, json/graph/python/chrono 1. Project level: thread, regex.
- **GeoModel:** GeoModelKernel 86, DBManager 16, Read 14, Helpers 8, Xml 7, ExpressionEvaluator 7, GeoGenericFunctions 2, Write 2, IOHelpers 2, Validation 2, GeoPrimitives 1.
- **ACTS:** Core, PluginJson, PluginGeoModel, PluginRoot, Fatras; OPTIONAL PluginGnn.
- **CORAL:** CoralBase 72, RelationalAccess 36, CoralKernel 36. **COOL:** CoolKernel 25, CoolApplication 13.
- **tdaq-common:** eformat 35, eformat_write 9, DataReader 7, CTPfragment 7, ers 6, EventStorage 5, hltinterface 4, DataWriter 3, MuCalDecode 3, dqm_core(_io) 2, dqm_dummy(_io) 2, RawFileName 2, circ_proc, chai, chaicontainer, EventStorageRecords, webdaq, webdaq-noroot, eformat_old 1.
- **tdaq (full)** is used by one package, `ByteStreamEmonSvc`: emon, ohroot, owl, is, omniORB4, omnithread, oh.
- **Qt5:** Core, Widgets, Gui, OpenGL, PrintSupport, Sql, Network (VP1 + a few tools).

Not referenced by any Athena CMakeLists, although built in AthenaExternals (V, grep):
- MKL, itksw-endec, hgtd-decoder, dqm-common (a `Finddqm-common.cmake` exists but has no users), VecGeom (only a Geant4 dependency) and HepMC2 (only a RELAX dependency in LCG);
- triSYCL (only `AthExSYCL`, an example);
- KLFitter (`KLFitterAnalysisAlgorithms` builds it only `if(XAOD_ANALYSIS)`, i.e. AnalysisBase, not Athena).

Unguarded `find_package` calls whose absence breaks the package (these need package filtering if the external is dropped; V from CMakeLists):
- traccc: `ActsGPUEvent`, `ActsGPUGeometry` and others;
- TritonClient: `AthTritonComps`;
- the generator interfaces (`Herwig7_i`, `Sherpa_i`, `Superchic_i`, `Hijing_i`, `Epos_i`, `Starlight_i`);
- `ByteStreamEmonSvc` (tdaq).

Guarded ones, which silently skip: `AthCUDA*` (`CMAKE_CUDA_COMPILER`), `AthHIP*`, `AthXRT*` (`ENV{XILINX_XRT}`), `ISF_FastCaloGpu`, `Epos4_i`, `Pepper_i`, G4PhysicsLists AdePT/Celeritas (`find_package(... QUIET)` + `if`), and valgrind in AthenaMonitoringKernel.

## 3. Per-external tables

### 3.1 Built by AthenaExternals (atlasexternals 2.1.91)

| external | ATLAS version / source | ATLAS patches | Athena pkgs | cf name | cf latest (versions) | platforms | licence | action |
|---|---|---|---|---|---|---|---|---|
| Gaudi | `atlas/Gaudi` **v40r4.002** = upstream v40r4 + 2 commits (93adb1ea "Remove RootFileHandler::setupSSL since ROOT won't provide SSL API", a4fec658 "Remove include TSSLSocket.h"); not in upstream v40r5/v40r6/v41r0 (V: `RootFileHandler.h` still has `setupSSL` in v40r6). Built with AIDA, XercesC, CLHEP (ATLAS), HepPDT, CppUnit, libunwind, rangev3, cppgsl, fmt, nlohmann_json, UUID, zlib, VDT, TBB, Eigen, Boost, Python; `GAUDI_CXX_STANDARD=23`; `GAUDI_USE_CUDA` if CUDA; headers into `include/Gaudi` | 2 commits (build compat) | all (PostConfig) | `gaudi` | **40.6** (40.4, 40.6) | **l64, la64 only**; feedstock `skip: osx` "lack of upstream support" | Apache-2.0 | 40.4 builds exist for root 6.40.2 × cxx 20/23 × clhep 2.4.7.2, and root 6.40.4 × cxx 20/23 × clhep 2.4.4.0/2.4.7.1/2.4.7.2, × py313/314, boost 1.90 (V). Use cf gaudi 40.4 on linux (check the SSL commits are not needed with cf ROOT); **osx-arm64 needs a Gaudi macOS port** (G: large). Check: cf installs Python to `$SP_DIR` and plugins to `$PREFIX/lib` (feedstock patch 0001 for the default plugin path) vs ATLAS layout |
| ACTS | **v47.7.0** release tarball; plugins Json, GeoModel, Root, Fatras; `ACTS_USE_SYSTEM_NLOHMANN_JSON`; if CUDA: GNN (onnx), traccc 1.6.0 + detray 0.111.0 + covfie + actsvg 0.4.51 + ModuleMapGraph | none | 46 (+traccc 9, detray 1) | `acts-core` | 45.5.1 (44.2–45.5.1) | all 3 | MPL-2.0 | build ACTS 47.7.0 ourselves (new output of our own, or bump acts feedstock + add plugins). traccc/detray/covfie/actsvg are missing on cf; `ActsGPU*` need them or must be filtered. ACTS downloads detray/covfie/actsvg at configure time unless system copies are given (G), which needs pre-fetched sources in a recipe |
| GeoModel | **6.29.0** (`GEOMODEL_BUILD_TOOLS=TRUE`, no visualization/FullSimLight in install) | none | 89 | `geomodel-core`, `-tools`, `-g4`, `-fullsimlight`, `-visualization`, `geomodel` | 6.31.0 (6.27–6.31) | **l64 only**; feedstock `skip: osx` (visualization needs X11/EGL) | Apache-2.0 | `geomodel-core` run-depends on geant4 11.4.2, qt6-main, soqt6, coin3d, hdf5 (V), which is heavy. Need la64 + oa64 builds; prefer a slimmer split or build ourselves. Pin 6.29.0 (exists on cf) |
| Geant4 | **ATLAS fork `atlas-simulation-team/geant4` v10.6.3.15**: 49 commits over v10.6.3 (G4AtlasRK4 stepper, G4GammaGeneralProcess backport + access changes, Woodcock tracking, Bertini/ATLASSIM fixes, C++20/LTO fixes) + 4 atlasexternals patches (cpp23, fsqrt, nosymlink, vecgeom-1.1.20); **static libs**, MT, TLS global-dynamic, GDML, `GEANT4_USE_USOLIDS=CONS;POLYCONE`, system CLHEP | yes, significant | 79 (+8 AtlasGeant4Utilities) | `geant4` | 11.4.2 (11.0.3–11.4.2; la64 also 10.7.4) | all 3 | Geant4 licence | **Athena includes `G4AtlasRK4.hh` unconditionally** (G4FieldManagerToolBase.cxx, Monopole G4mplEquationSetup) → does not compile against upstream G4. Options: (a) add the G4AtlasRK4 files as a patch to a cf-style geant4 11.x build, (b) patch Athena to guard AtlasRK4, (c) package the ATLAS fork (v11.2.2.3 has G4AtlasRK4, V) as a separate non-conflicting package. G4 data: cf has `geant4-data-*` for 11.4.2 only |
| VecGeom | 1.1.21 + 3 patches | yes (compat) | 0 (G4 only) | `vecgeom` | 2.0.0 | all 3 | Apache-2.0 | drop USolids (G) or new build |
| VecCore | 0.8.2 | none | 0 | `veccore` | 0.8.2 | all 3 | Apache-2.0 | ok |
| CLHEP | `atlas-sw-git/CLHEP` **CLHEP_2_4_7_1_atl01** = 2.4.7.1 + 5 commits: RandGaussZiggurat/RandExpZiggurat without `thread_local`, `makeConstants` qualification, RandBinomial `private`→`protected`, Ziggurat rounding fix; + `overridden-virtual-warning.patch` | **yes, needed** (RandBinomialFixedP uses a protected member, V) | 314 | `clhep` | 2.4.7.2 (2.4.7.1 available; cf pins clhep in zip with geant4) | all 3 | LGPL-3.0 (GPL-3 per GitLab detection) | carry the 5 commits as patches; ask upstream CLHEP to take them. Changing access specifiers is ABI-neutral (G), so an ATLAS-patched clhep could replace cf's |
| onnxruntime | **1.26.0 prebuilt Microsoft tarball** (`onnxruntime-linux-{x64,aarch64}-1.26.0.tgz`, CUDA-13 GPU variant on x64) | n/a | 30 | `onnxruntime-cpp` | 1.30.0 (1.24.2–1.30.0; 1.26.0 has cpu, cuda129, cuda130 builds) | all 3 | MIT | use cf `onnxruntime-cpp` 1.26.x (cpu) |
| lwtnn | 2.14.1 | none | 22 | `lwtnn` | 2.14.2 (2.14.1) | all 3 | MIT | ok (cf built on Eigen 3.4; ATLAS uses Eigen 3.4.1: consistent) |
| nlohmann_json | 3.12.0 (from LCG `jsonmcpp`; atlasexternals only if not found) | none | 37 | `nlohmann_json` | 3.12.0 | all 3 | MIT | ok |
| GoogleTest | 1.17.0 | none | 52 + 11 GMock | `gtest`, `gmock` | 1.18.0 (1.17.0) | all 3 | BSD-3 | ok |
| Coin3D | coin-5297f6c (2023-04-18; Coin 4.0.1 cmake) | none | 25 | `coin3d` | 4.0.10 | all 3 | BSD-3 | ok (VP1) |
| SoQt | soqt_ea5cd76 (1.6.0a, Qt5) | none | 7 | `soqt` | 1.6.3 (l64 also 1.6.0a) | all 3 | BSD-3 | ok (VP1) |
| Simage | Coin3D-simage-2c958a61ea8b | libpng_centos7.patch | (via SoQt/Coin) | `simage` | 1.8.3 | all 3 | BSD-3 | ok |
| prmon | 3.3.0 | none | runtime (job transforms) | `prmon` | 3.3.0 | **l64, la64** | Apache-2.0 | ok on linux; Linux-only by design (/proc) |
| yampl | v1.2 | none | 2 (AthenaMPTools, AthenaServices) | — | missing | — | **none in repo** (vitillo/yampl) | new recipe + licence clarification, or build AthenaMP without it (G: needs patching, `find_package(yampl)` unguarded but libs appear only in include/link vars) |
| boost-mpi3 (bmpi3) | v0.81 + patch; header-only; config requires `MPI::MPI_CXX`, Boost.serialization | yes (small) | 1 (**AthenaServices, REQUIRED**) | — | missing | — | Boost-1.0 | new header-only recipe (noarch); runtime dep on openmpi/mpich (cf: openmpi 5.0.11, mpich 5.0.2, all 3) |
| dSFMT | 2.1 (bundled source in atlasexternals), builds `libdSFMT-sse2.a` + `libdSFMT-std.a` | — | 1 (AtlasCLHEP_RandomGenerators) | `dsfmt` | 2.2.3 | **l64 only** | BSD-3 | vendor as ATLAS does (static, tiny) |
| APTypes | Xilinx ap_types 200a9ae + ATLAS patch (`ap_private.h`) | yes | 1 (GlobalSimulation) | — | missing | — | Apache-2.0 | header-only recipe; conflicts with the CMS `hls-arbitrary-precision-types` recipe's files (same headers, different fork) |
| VecMem | 1.27.0 | none | 14 (AthDevice*, EFTracking, ActsGPU*) | — | missing | — | MPL-2.0 | new recipe (small CMake lib) |
| Triton | r24.12 client/common/core + numactl 2.0.19 + 9 patches | yes | 2 (AthTritonComps, FlavorTagInference) | `tritonclient` (python only) | — | — | BSD-3 | skip (filter AthTritonComps; FlavorTagInference guard to check) |
| CheckerGccPlugins | in-tree gcc plugin (thread-safety static checker) | — | build-time only | — | — | — | Apache-2.0 | skip (not needed to build; gcc-only) |
| GPerfTools | scripts only; wraps LCG gperftools + libunwind | — | 1 (PerfMonGPerfTools) | `gperftools` 2.18.90, `libunwind` 1.8.3 | l+la+oa / **l+la** | — | BSD / MIT | ok on linux, optional |
| flake8_atlas | in-tree flake8 plugin | — | dev only | `flake8`, `flake8-bugbear`, `flake8-builtins` | noarch | — | Apache-2.0 | dev-only |
| PyModules | pip installs **pyami 5.1.10, histgrinder 0.1.6, lark 1.0.0, nanobind 2.10.2** from ATLAS pip mirror | — | runtime | `pyami-atlas`/`pyami-core` 5.1.10, `lark` 1.3.1, `nanobind` 3.1.0 (2.10.2) | noarch | — | LGPL-3 / Apache-2.0 / MIT / BSD | only **histgrinder** missing (Apache-2.0, pure python) → new noarch recipe |
| MKL | oneMKL 2022.0.2 offline installer (x86_64 only) | — | 0 | `mkl` | — | — | proprietary (ISSL) | skip (unused) |
| triSYCL | fbfc9c4d | — | 1 example | — | missing | — | Apache-2.0 w/ LLVM exc. (G) | skip |
| itksw-endec / hgtd-decoder | v4.0.0 / hgtd-sw-00-02-01 | — | 0 (V, grep) | — | missing | — | Apache-2.0 | skip unless a package starts using them |

### 3.2 From LCG_110_ATLAS_5: C++/system externals Athena uses

| external | LCG version | Athena pkgs | cf name | cf latest | platforms | notes / action |
|---|---|---|---|---|---|---|
| ROOT | 6.40.02 (upstream tarball, no patches in LCG logs), C++23, builtin clang/LLVM 20, features: davix, xrootd, vdt, ssl, sqlite, fftw3, fitsio, mathmore, tmva(+cpu, cudnn, sofie), roofit, root7, dataframe, pyroot, tpython, runtime_cxxmodules, gdml, opengl/x11/webgui, fortran, unuran | 518 | `root_base` / `root` | 6.40.04 (6.36.14–6.40.04) | all 3 | **6.40.02 cxx23 py313 exists on all 3**. See §5 |
| Boost | 1.91.0 | 153 | `libboost-devel`, `libboost-python-devel` | 1.92.0 (1.85–1.92) | all 3 | use 1.90 to match cf gaudi/geant4 builds (run_exports pin x.x) |
| TBB | 2022.2.0 | 24 | `tbb-devel` | 2023.1.0 | all 3 | ok |
| Python | 3.13.11 | 11 | `python` | 3.13/3.14 | all 3 | ok |
| Eigen | 3.4.1 | 29 | `eigen` / `libeigen` | 5.0.1 (3.4.0) | all 3 | use 3.4.0 (3.4.1 not on cf) |
| XercesC | 3.3.0 | 3 + Gaudi | `xerces-c` | 3.3.0 | all 3 | ok |
| XRootD | 6.1.1 | 2 + ROOT | `xrootd` | 6.1.1 | all 3 | ok |
| Davix | 0.8.10 | 1 + ROOT | `davix` | 0.8.10 | all 3 | ok |
| HepMC3 | 3.3.1 | 3 (AtlasHepMC: HepMC3, HepMC3search) | `hepmc3` | 3.3.1 | all 3 | ok; cf build has no rootIO, and Athena installs a dummy rootmap to suppress rootIO anyway (GeneratorObjects) |
| HepPDT | 2.06.01 | 2 + Gaudi | `heppdt` | 2.06.01 | all 3 | ok |
| FastJet / fjcontrib | 3.5.1 / 1.102 | 20 / 9 | `fastjet`, `fastjet-contrib` | 3.5.1.5 / 1.104 | all 3 | ok |
| HDF5 | 1.14.6 | 5 (CXX, HL) | `hdf5` | 2.2.0 (pin 1.14.6) | all 3 | ok |
| HighFive | 2.10.1 | 2 | `highfive` | 3.3.0 (2.10.1) | all 3 | pin 2.10.1 |
| VDT | 0.4.4 | 7 | `vdt` | 0.4.4 | all 3 | ok |
| GSL | 2.8 | 8 | `gsl` | 2.8 | all 3 | ok |
| FFTW | 3.3.10 | 2 | `fftw` | 3.3.11 | all 3 | ok |
| libxml2 | 2.10.4 | 2 | `libxml2` | 2.15.4 | all 3 | ok (G) |
| SQLite | 3.32.3 | 2 + CORAL | `sqlite`/`libsqlite` | 3.53.4 | all 3 | ok |
| libuuid | system | 9 + Gaudi | `libuuid` | 2.42.4 | all 3 | ok |
| zlib / curl / openssl / expat / lz4 | system / LCG | 2/2/2/1/1 | `libzlib`, `libcurl`, `openssl`, `expat`, `lz4-c` | current | all 3 | ok |
| protobuf / gRPC / abseil | 7.34.1 / 1.78.1 / 20250512.2 | 2 / 2 | `libprotobuf`, `libgrpc`, `libabseil` | 7.36.2 / 1.83.1 / 20260817 | all 3 | ok (EventIndexProducer, FlavorTagInference, Triton) |
| CppUnit | 1.15.1 | 1 + Gaudi | `cppunit` | 1.15.1 | all 3 | ok |
| AIDA | 3.2.1 | Gaudi | `aida` | 3.2.1 (noarch) | — | ok |
| rangev3 / cppgsl / fmt | 0.12.0 / 4.2.0 / 12.1.0 | Gaudi | `range-v3`, `ms-gsl`, `fmt` | 0.12.0 / 5.0.1 (4.2.x) / 12.2.0 | all 3 | ok |
| BLAS/LAPACK | openblas 0.3.33 | 1 (TrkAlgebraUtils) | `libopenblas`, `liblapack` | 0.3.34 / 3.11 | all 3 | ok |
| Qt5 (+pyqt5) | 5.15.15 | 35 (VP1, tools) | `qt-main` 5.15, `pyqt` | 5.15.15 | all 3 | ok; conda-forge is moving to Qt6, so keeping Qt5 is a long-term risk (G) |
| OpenGL/glib/libffi/libxkbcommon | system | 2/1/1/1 (VP1Algs) | `libgl`, `glib`, `libffi`, `libxkbcommon` | — | libxkbcommon l+la only | ok on linux |
| frontier_client | 2.10.2 | runtime (CORAL FrontierAccess) | — | **missing** | — | reuse CMSSW-repo `recipes/frontier-client` (same version; deps expat, zlib, openssl, pacparser; cf pacparser 1.5.2 on all 3) |
| MySQL (MariaDB client) | 10.11.16 | runtime (CORAL MySQLAccess) | `mysql`, `mysql-connector-c` | 9.7 / 6.1.11 | mysql all 3 | optional; drop MySQLAccess |
| Oracle instant client | 19.19 | 5 (links `${ORACLE_LIBRARIES}` if found, but **no Athena source includes oci.h/occi**, V) | `oracle-instant-client` | 23.7 | **l64 only**, proprietary | drop; CORAL OracleAccess not built |
| cx_Oracle / oracledb | 8.3.0 / 3.4.2 | 9 (python) | `cx_oracle`, `oracledb` | 8.3.0 / 26.0.1 | all 3 | cx_Oracle needs the instant client at runtime; oracledb thin mode does not |
| gdb (libbfd, libiberty, libsframe) | 17.2 | 1 (AthenaAuditors: `find_package(gdb COMPONENTS bfd iberty sframe)`) | `gdb`, `binutils` | 18.1 | gdb all 3 | no `libbfd`/`libiberty` package on cf (binutils_impl may ship them, unverified). FPE-auditor stack traces; guard or patch (G) |
| valgrind | 3.27.0 | 3 (headers only, guarded in one) | `valgrind` | 3.27.1 | **l+la** | optional |
| gperftools / pprof | 2.18.1 / 54271f7 | 1 | `gperftools` / — | 2.18.90 / pprof missing (Go) | all 3 / — | optional |
| CUDA / cuDNN | 13.3.1 / 9.20 | 3 + ACTS GNN/traccc + onnxruntime GPU | `cuda-nvcc`, `cudnn` | 13.4.92 / 9.26 | **l+la only** | out of scope initially |
| graphviz / pygraphviz | 12.2.1 / 1.11 | 1 | `graphviz`, `pygraphviz` | 14.1.2 / 2.0.2 | all 3 | ok |
| libzip | 1.11.4 | 1 (Sherpa_i) | `libzip` | 1.11.4 | all 3 | ok |

### 3.3 TDAQ

| item | version | Athena use | cf | licence | packageable? |
|---|---|---|---|---|---|
| **tdaq-common** | 14-00-00 (`TDAQ_COMMON_VERSION 14.0.0`, `LCG_110`), cmake_tdaq-based; platforms: x86_64/aarch64 el9/el10, gcc15/16 | **64 packages**: all `*ByteStream*`/`*_CnvTools` converters (Pixel, SCT, TRT, LAr, Tile, Muon RPC/TGC/MDT/CSC/MM/sTGC/NSW, L1Calo, L1Topo, CTP, AFP, ALFA, LUCID, ZDC, BCM, ITk), `Event/ByteStream*`, `HLT/*` (TrigServices, TrigByteStreamCnvSvc, TrigDFEmulator), `Trigger/*` (TrigSteeringEvent, TrigOutputHandling, TrigT1Result…), `DataQuality/{DataQualityInterfaces,dqm_algorithms}`, TestBeam/TBCnv, Tools/FilePeeker | missing | **Apache-2.0** in every component dir (df_ef_interface, webdaq have no LICENSE file) | **Yes (G: moderate).** All 18 component repos are public (`git ls-remote` works), the umbrella `atlas-tdaq-software/tdaq-common` is **not** (auth required). Deps: Boost (thread, date_time, program_options, python, unit_test_framework), ROOT, zlib, uuid, curl, nlohmann_json, TBB, Python. `cmake_tdaq`'s `tdaq_project(... USES LCG ...)` expects an LCG layout, so it must be taught to use a conda prefix (G). macOS: never built (G) |
| CORAL / COOL | CORAL_3_3_20 / COOL_3_3_20 (built inside tdaq-common `TDAQCExternal`) | 79 / 25 | missing | **no LICENSE** | recipe feasible (CMake), CMSSW repo's `coral` recipe is a different fork (CORAL_2_3_21 CMS, SCRAM-built), so only the patches for gcc15/py3.12/macOS can be reused. Same licence blocker as CMSSW |
| CrestApi / chai | 6.2.12 / 2.1.0 | 2+ / 4 | missing | none / Apache-2.0 | recipe feasible; chai uses nanobind (tdaq's copy) |
| **tdaq (full)** | 14-00-00 | **1 C++ package** (`HLT/Event/ByteStreamEmonSvc`: emon, ohroot, owl, is, omniORB4, omnithread, oh) + online-only Python (`ispy`, `ipc`, `oh`, `pm`, `libpbeastpy`) in RecExOnline, TrigT1CaloMonitoring, TileMonitoring, EventDisplaysOnline, DQOnlinePostprocessing, TrigCostAnalysis/RatesAnalysis online scripts, `athenaEF_tdaq_infra.py`, … | missing | mixed | **No.** CORBA-based online stack; exclude ByteStreamEmonSvc via package filter; the Python scripts only fail when run |
| dqm-common | 01-09-00 exists on CVMFS | 0 (V) | — | — | not needed |

### 3.4 Generators (from LCG_110_ATLAS_5 `MCGenerators`)

| generator | LCG version | Athena user | cf name | cf latest | platforms | action |
|---|---|---|---|---|---|---|
| Pythia8 | 8.317 | Pythia8_i, Pythia8B_i, EvtGen_i, Hto4lControl, Prophecy4fControl, External/Pythia8 | `pythia8` | 8.312 | all 3 | bump to 8.317 |
| EvtGen | 2.2.1 | EvtGen_i | `evtgen` | 2.2.3 | all 3 | ok (cf built vs photos + `tauloa` + pythia8 8.312) |
| Photos++ | 3.64.atlas1 | Photospp_i, EvtGen_i | `photos` | 3.64 | all 3 | ATLAS patch content unknown |
| Tauola++ | 1.1.9.atlas2 | Tauolapp_i, EvtGen_i | **`tauloa`** (sic) | 1.1.9 | all 3 | ATLAS patch content unknown |
| LHAPDF | 6.5.5 | 7 | `lhapdf` | 6.5.6 | all 3 | ok; PDF sets are data (`/cvmfs/sft.cern.ch/lcg/external/lhapdfsets`) |
| Rivet / YODA / Contur | 4.1.2 / 2.1.2 / 3.1.3 | 4 / 4 / 1 | `rivet`, `yoda`, `contur` | 4.1.4 / 2.1.4 / 3.1.5 | all 3 (contur noarch) | ok |
| Herwig7 / ThePEG | 7.3.0p1 (`herwig3`) / 2.3.0 | Herwig7_i | — / `thepeg` | — / 2.2.3 | ThePEG **l+la** | Herwig in staged-recipes #33684 |
| Sherpa | 3.0.4 | Sherpa_i | `sherpa` | 3.0.0 | all 3 | bump |
| OpenLoops | 2.1.4.250729 | Herwig7_i, PowhegControl, Sherpa_i | — | missing | — | new recipe (Fortran; process libs are downloads) |
| MadGraph5_aMC | 3.5.11.atlas16 | MadGraphControl (runtime) | `mg5amcnlo` | 3.5.7 | all 3 | ATLAS-patched; runtime only |
| Powheg-Box | compilebox 08.14 (**x86_64 only** in LCG) | PowhegControl (+ nlox, recola, ggvvamp, qqvvamp, chaplin, ginac, cln) | — | missing | — | skip initially |
| Superchic / Apfel / SFGen | 5.7.1 / 3.1.0 / 1.03.atlas2 | Superchic_i, SFGen_i | — | missing | — | new recipes |
| Starlight | r330 | Starlight_i | — | missing | — | new recipe |
| Hijing | 1.383bs.2.atlas20260625 | Hijing_i | — | missing | — | new recipe (ATLAS-patched Fortran) |
| CRMC (EPOS-LHC) | 2.0.1p5 | Epos_i | — | missing | — | new recipe |
| EPOS4 | 4.0.3.atlas3 (**x86_64 only**) | Epos4_i (guarded) | — | missing | — | skip |
| Pepper | 1.8.0 + kokkos (**x86_64 only**) | Pepper_i (guarded) | — (kokkos exists) | missing | — | skip |
| Prophecy4f / Hto4l | 3.0.2 / 2.02 | 1 / 1 | — | missing | — | skip initially |
| MCFM, VBFNLO, NJet, FeynHiggs, GoSam, qgraf, FORM, looptools, collier, qd, syscalc, pythia6, hydjet, pyquen, thep8i | various | no direct `find_package` (runtime/Powheg/MG deps) | partial (feynhiggs l64, collier, qd) | — | — | skip |

### 3.5 Python runtime (imports across Athena `python/` + `bin/`, 5,773 files; V)

Third-party top-level imports (count = files):
- ROOT 548, cppyy 92 (ROOT);
- numpy 51, yaml 22, matplotlib 20, pandas 14, requests 10, tqdm 8, future/`past` 8, pyAMI 34, cx_Oracle 12, sqlalchemy 4, onnxruntime 4, stomp 5, histgrinder 7, awkward 4, uproot 2, scipy 2, IPython 4, pygraphviz 2, psutil, distro, boto3/botocore, pyparsing, six, packaging, tomli, uncertainties, seaborn, colorlog, cherrypy, genshi, python-gitlab, MySQLdb, pytz, lark, pyHepMC3, lhapdf/yoda/rivet (python);
- torch 4, xgboost 2 and lightgbm 2, all in optional scripts.

**All are on conda-forge except `histgrinder`.** Conda names are `pyyaml`, `stomp.py`, `mysqlclient`, `future`, `python-gitlab`, `pyami-atlas`; `pyHepMC3` ships in the `hepmc3` package.

Python modules shipped by the C++ externals, which come along with those packages:
- `eformat`, `libpyeformat_helper`, `libpyevent_storage`, `ers` (tdaq-common);
- `PyCool`, `coral` (COOL/CORAL);
- `pycrest`, `chai` (CrestApi/chai);
- `GaudiKernel`, `GaudiPython`, `GaudiConfig2`, … (Gaudi).

Online-only and not packageable: `ispy`, `ipc`, `oh`, `pm`, `libpbeastpy` (tdaq).

## 4. The hard ones in detail

1. **Geant4 (simulation layer only, but also 79 packages).**
   - ATLAS runs a 6-year-old Geant4 series with physics validated for Run 3.
   - conda-forge only has 11.x (plus 10.7.4 on la64).
   - Beyond the version gap, the ATLAS fork adds public classes that Athena code references: `G4AtlasRK4` unconditionally; `G4WoodcockProcess` only in the AdePT/HepEm optional sources.
   - Building simulation needs either a patched Geant4 11 or the ATLAS fork's 11.2.2.3 tag.
   - Results would differ from ATLAS production (10.6) in any case.
   - ATLAS links G4 **statically** (to avoid TLS overhead, G). conda-forge ships shared libs. Athena's `FindGeant4` uses the Geant4 CMake config, so shared should work (V: no static-specific logic).
2. **Gaudi on macOS.** No conda-forge build; upstream Gaudi does not support macOS (feedstock comment). Every Athena component depends on Gaudi, so osx-arm64 depends entirely on porting Gaudi (plugin service, `dlopen`, `/proc`, ELF-specific code; G). This mirrors CMSSW's macOS track but the dependency is external.
3. **ACTS pin.**
   - ATLAS moves ACTS majors frequently: 47.7.0 now vs 45.5.1 on cf.
   - ACTS must be rebuilt for every Athena release with its plugins (Json, GeoModel, Root, Fatras), and it depends on GeoModel (plugin) and ROOT (plugin root_base pin), so it belongs in our own recipe set, versioned with Athena, not in the generic feedstock.
4. **tdaq-common.** Mandatory for RAW → ESD/AOD reconstruction and trigger. It is packageable (Apache-2.0, public component repos, few deps), but its build system (`cmake_tdaq`) is LCG-centric and has never been built outside EL9/gcc (G).
5. **CORAL/COOL/CrestApi: no licence files.** The same blocker as the CMSSW CORAL recipe, now for three packages. Conditions access (IOVDbSvc, 79 packages) cannot work without them.
6. **GPU-built externals.** The reference release is CUDA-enabled, so AthenaExternals contains traccc, detray, covfie, actsvg, ModuleMapGraph, the Triton server and `GaudiCUDA`.
   - A CPU-only conda build must build ACTS with `ATLAS_ACTS_BUILD_TRACCC=OFF` and `ATLAS_ACTS_USE_GNN=OFF`.
   - It must filter `ActsGPU*`, `AthTriton*`, `TracccTritonClient` and `EFTracking*` packages whose `find_package` calls are unguarded.
   - `vecmem` is still needed on CPU (`AthDevice*`).
7. **x86_64-only pieces in LCG:** EPOS4, MCFM, nlox, Pepper, Powheg (compilebox), MKL, oracle client. None of them is core.

## 5. ROOT version pinning and C++ standard

- **ATLAS:**
  - ROOT **6.40.02** from LCG_110_ATLAS_5: plain upstream source tarball (`download-ROOT-6.40.02.cmake`), no patch step in the logs.
  - `-DCMAKE_CXX_STANDARD=23` and `R__CONFIGUREFEATURES "cxx23 … builtin_clang builtin_llvm … runtime_cxxmodules …"` (V, `RConfigOptions.h`).
  - Athena itself is C++23. `AtlasCompilerSettings.cmake` picks 23 for gcc ≥15 or clang ≥22, else 20, and the installed `PreConfig.cmake` hard-sets `CMAKE_CXX_STANDARD 23`.
- **conda-forge:**
  - `root_base` 6.40.02 and 6.40.04 exist on **all three** platforms in both `root_cxx_standard` 20 and 23 variants, for py 3.10/3.11–3.14 (V).
  - The global pinning zips `root_base`/`root_cxx_standard` as {6.36.10/20, 6.38.4/20, 6.38.4/23, 6.40.2/23, 6.40.2/20}, so **6.40.2 + C++23 is a first-class pinned variant**. (The pinning file says 6.40.2; the available builds are 6.40.02/6.40.04.)
  - cf ROOT uses an external `clangdev`, not builtin LLVM, which is fine for users. The other LCG ROOT features are expected in cf ROOT (not individually verified).
- **Pinning semantics:** `root_base` has x.y.z run_exports (e.g. gaudi 40.6 depends on `root_base >=6.40.4,<6.40.5.0a0`, V). Every ROOT-linked package we ship (Gaudi if rebuilt, ACTS PluginRoot, tdaq-common dqm_core/webdaq/HistogramStyles, COOL/PyCool (G), all Athena layers) must be rebuilt together per ROOT patch release.
- **cf gaudi 40.4** exists on l64 and la64 for root 6.40.2 × cxx23 × py313, but only with clhep 2.4.7.2. The clhep 2.4.7.1 builds are against root 6.40.4 (40.4 and 40.6). So ATLAS's exact combination (6.40.02 + clhep 2.4.7.1) is not available. Either move to root 6.40.04 (a patch release, G: low risk), or rebuild Gaudi ourselves. The patched ATLAS CLHEP needs a Gaudi rebuild anyway if the clhep build string changes. **40.6** only has 6.40.4 builds.
- **RNTuple.** Athena uses `ROOTNTuple` (5 packages) and is moving its persistent format to RNTuple. Keeping the same ROOT minor as ATLAS matters for file compatibility and should be treated as a hard pin (G).
- **macOS:**
  - conda-forge uses clang 21 + libc++. ATLAS's own logic would choose C++20 for clang <22. To match a cxx23 `root_base` (the `root_cxx_standard` mutex), the conda build must pass `-DCMAKE_CXX_STANDARD=23` on osx as well, or use the cxx20 ROOT variant on osx only.
  - Whether Athena compiles as C++20 is unknown (G: ATLAS still supports C++20 in the logic above).
- **Other ROOT-coupled pins to align:**
  - Boost: cf gaudi and geant4 are built vs 1.90, so choose 1.90 over ATLAS's 1.91 and the cf pin 1.88;
  - TBB: cf root_base needs tbb ≥2023; ATLAS uses 2022.2 (same ABI);
  - Python 3.13;
  - clhep 2.4.7.1 (zipped with geant4 11.3.2 in cf pinning, so a patched clhep 2.4.7.1 plus a geant4 11.3.x/11.4.x decision must be made together).

## 6. Implications for conda-forge packaging

1. **Our layer 0 of new recipes, before any Athena code:**
   - tdaq-common (subset);
   - CORAL + COOL (upstream 3_3_20, CMake);
   - frontier-client (reuse from the CMSSW repo);
   - CrestApi + chai;
   - vecmem, yampl, boost-mpi3 and APTypes (header-only);
   - histgrinder (noarch);
   - a patched CLHEP (`clhep` with ATLAS's 5 commits, or ATLAS-only output);
   - ACTS 47.7.0 with plugins;
   - GeoModel 6.29.0 with only core+tools, for all 3 platforms.

   All are CMake projects with small dependency sets, except ACTS, which is large.
2. **Reuse from conda-forge as-is:** ROOT 6.40.02 cxx23, Boost 1.90, TBB, Python 3.13, Eigen 3.4.0, XercesC, XRootD, Davix, HepMC3, HepPDT, FastJet(+contrib), HDF5, HighFive 2.10.1, VDT, GSL, FFTW, nlohmann_json, fmt, onnxruntime-cpp 1.26, lwtnn, gtest/gmock, CppUnit, AIDA, range-v3, ms-gsl, protobuf/grpc, Qt5/Coin3D/SoQt/simage, openmpi, LHAPDF, Rivet, YODA, and the whole Python stack.
3. **Gaudi:** use cf `gaudi` 40.4 on Linux if Athena builds against its layout (Python in site-packages, plugin path, include paths). Otherwise rebuild the ATLAS fork (2 extra commits) in our recipe set. **osx-arm64 is blocked until Gaudi is ported.** Decide early whether osx-arm64 is a realistic target for Athena at all (unlike CMSSW, where the framework was in-house).
4. **Simulation is a separate decision.** Either Geant4 11 + ATLAS patches (and results differing from production) or package the ATLAS G4 fork. The reconstruction/analysis layers do not need Geant4 at runtime, although 79 packages `find_package(Geant4)`, so the simulation layer should be split off by package filter.
5. **Exclude by package filter from the start:**
   - `ByteStreamEmonSvc` (full tdaq);
   - `AthTriton*`, `ActsGPU*`, `TracccTritonClient`, `EFTracking*` FPGA/XRT, `AthCUDA*`/`AthHIP*` (these self-skip);
   - generator interfaces whose generator is missing: Herwig7_i, Superchic_i, SFGen_i, Starlight_i, Hijing_i, Epos_i, Epos4_i, Pepper_i, PowhegControl-linked, Prophecy4f/Hto4l;
   - VP1, which is optional but on conda-forge.
6. **Licences to clarify with CERN/ATLAS before submitting to conda-forge:** CORAL, COOL, CrestApi, yampl. Also the "other" licence of the atlasexternals repo, and whether Athena itself (Apache-2.0) can ship ATLAS-internal data paths.
7. **Pins file for the Athena recipes** (analogous to CMSSW's `variants.yaml`): root_base 6.40.02 (or 6.40.04 to reuse cf gaudi with clhep 2.4.7.1) / root_cxx_standard 23, libboost 1.90, clhep 2.4.7.1 (patched), python 3.13, eigen 3.4.0, highfive 2.10.1, gaudi 40.4 (linux), acts 47.7.0, geomodel 6.29.0, tbb 2023, hepmc3 3.3, onnxruntime-cpp 1.26.
8. **Runtime data and environment** (not externals, but they surface here): G4 data (`G4PATH`), LHAPDF sets, conditions (`DATAPATH`, `CALIBPATH` pointing at CVMFS), `TDAQ_DB_PATH`, Frontier server config (`FRONTIER_SERVER`). The conda activation must replace these CVMFS defaults in `env_setup.sh`.

## 7. Open questions

1. Does Athena build and run against cf `gaudi` 40.4 unchanged? Two things to check: whether the missing SSL-removal commits matter with cf ROOT 6.40, and whether the install layout differs from ATLAS's `include/Gaudi` prefix (ATLAS passes `CMAKE_INSTALL_INCLUDEDIR=include/Gaudi`).
2. Can Gaudi be ported to macOS at reasonable cost? This decides whether osx-arm64 is in scope for Athena.
3. Geant4 strategy: patched cf-style Geant4 11.x vs the ATLAS fork (v11.2.2.3 has G4AtlasRK4) vs the 10.6 fork. What else in Athena simulation breaks on 11.4 (Athena has `G4VERSION_NUMBER >= 1100` guards, so ATLAS tests 11.x somewhere, G)?
4. Can `cmake_tdaq`/tdaq-common be built outside an LCG view (against a conda prefix)? Is the private umbrella repo `atlas-tdaq-software/tdaq-common` needed, or do the public components plus the CVMFS-installed top-level `CMakeLists.txt` suffice?
5. Licences for CORAL, COOL, CrestApi, yampl (and chai's use of nanobind from tdaq).
6. Can a CPU-only AthenaExternals-equivalent (no traccc/GNN/Triton) build all remaining Athena packages? ATLAS's reference build always has CUDA, so the non-CUDA configuration is less tested (G).
7. Does Athena compile as C++23 with clang 21/libc++ on osx-arm64, or as C++20 against a cxx20 ROOT?
8. What exactly do the `.atlasN` generator patches in lcgcmake change (photos++, tauola++, hijing, madgraph, SFGen, epos4)? Are they needed for Athena's interfaces or only for physics settings?
9. `AthenaAuditors` needs libbfd/libiberty/libsframe from gdb. Which conda-forge package provides these, if any (binutils_impl?), and does the auditor degrade gracefully without them?
10. Is `bmpi3` (MPI) really needed at runtime by `AthenaServices`, or only for an MPI event-loop mode? It is `REQUIRED` at configure time either way.
11. ACTS: can conda-forge's acts feedstock be bumped to follow ATLAS, or do we keep ACTS in our own recipe set tied to Athena releases (recommended, G)?
12. GeoModel: will the geomodel feedstock add la64/oa64 and a light (no Qt6/Geant4) core output, or do we build GeoModel 6.29.0 ourselves?
