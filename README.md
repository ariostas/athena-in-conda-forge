# Athena in conda-forge

This repository is an effort to package [Athena](https://gitlab.cern.ch/atlas/athena), the
software framework of the ATLAS experiment at CERN, for [conda-forge](https://conda-forge.org).
The goal is to install it with

```sh
conda install -c conda-forge athena-analysis   # or pixi add / mamba install
```

on **linux-64, linux-aarch64 and osx-arm64**, without CVMFS or an ATLAS-specific environment.

It is a fork of [conda-forge/staged-recipes](https://github.com/conda-forge/staged-recipes), the
entry point for new conda-forge packages. The original staged-recipes README is in
[README-staged-recipes.md](README-staged-recipes.md). It follows the same approach as
[cmssw-in-conda-forge](https://github.com/ariostas/cmssw-in-conda-forge), which does this for
CMSSW.

> **Status: proof of concept.** All of Athena but 30 packages builds in ten layers that pass their
> tests on linux-aarch64, from the framework to simulation and derivations, with an `athena`
> metapackage and a developer workflow. On linux-64 (M8) every external and all ten layers pass
> too; on osx-arm64 (M8, in progress) every external and the layers up to reco-tracking do:
> `athena.py` runs on a Mac. Nothing has been submitted to conda-forge yet.

The reference release is Athena [`release/25.0.73`](https://gitlab.cern.ch/atlas/athena/-/tree/release/25.0.73).

## Why this is hard

- **Size:** Athena is a monorepo of about 2,000 packages and 15k C++ translation units (not
  counting tests). A full build is far too large for a single conda-forge CI job, so it has to be
  split into several packages that are built on top of each other.
- **Build system:** ATLAS builds with its own CMake framework,
  [AtlasCMake](https://gitlab.cern.ch/atlas/atlasexternals), on top of an `AthenaExternals`
  project and an LCG release of externals from CVMFS. Some externals are ATLAS forks
  (Gaudi, CLHEP), and several are not on conda-forge at all (CORAL, COOL, the CREST clients,
  tdaq-common, yampl).
- **Build-time code execution:** the build runs freshly built code: ROOT dictionaries,
  Gaudi's configurable generation (`genconf`), the class ID database (`clid.db`) and python
  configuration databases.
- **Platforms:** ATLAS builds for EL9 with GCC (x86-64 and aarch64). macOS has only ever been
  supported for the AnalysisBase subset.
- **Runtime data:** jobs read calibration files (GroupData), the geometry database and detector
  conditions, all of which normally come from CVMFS.

The full analysis, the decisions and a progress log are in [PLAN.md](PLAN.md).

## Approach

- **Build with AtlasCMake inside rattler-build, against conda-forge's externals.** Athena's own
  CMake code is used unchanged. `athena-externals` is ATLAS's `AthenaExternals` project itself,
  configured with no bundled externals: AtlasCMake and AtlasLCG with a few patches (from Chris
  Burr's conda proof of concept, plus two of ours), find modules for conda-forge's layouts and a
  conda PostConfig.
- **Use conda-forge externals** (ROOT 6.40 C++23, Boost, TBB, Eigen, HepMC3, onnxruntime, ...).
  Missing ones get their own recipes. Gaudi is built from ATLAS's fork with Athena's compiler
  (conda-forge's gaudi is a gcc 14 build, which is ABI-incompatible with gcc 15 code that uses
  `std::format`).
- **Split Athena into layers, each its own ATLAS project.** Each layer is built against the
  installed layers below it, as ATLAS stacks AthSimulation or AthAnalysis on AthenaExternals,
  and installed in the CVMFS layout, `$PREFIX/opt/athena/<Project>/25.0.73/InstallArea/<platform>`.
  So no two packages share files, and ATLAS's own `setup.sh` chaining works. The layers are
  pinned exactly to each other.
- **Replace `asetup` with conda activation scripts**, which source the layer's `setup.sh` and
  save and restore what it changes. No CVMFS is needed at runtime; it is used when mounted.
- **Choose layers by what they deliver**, not by an even split of the code
  ([layers.py](athena-notes/analysis/scripts/layers.py)), and check each one by running its
  target jobs in ATLAS's own release from CVMFS and listing the packages they load.
- **Test against ATLAS's release.** Each layer's tests run real jobs and compare their output
  with what ATLAS's release writes for the same job: dumps of every object, n-tuples, geometry
  counts. Each layer also builds and runs ATLAS's own unit tests where they need no input files.

## Status

| Package | Recipe | linux-aarch64 | linux-64 | osx-arm64 |
|---|---|---|---|---|
| `boost-mpi3` (C++ wrapper for MPI-3, with ATLAS's patch) | [recipes/boost-mpi3](recipes/boost-mpi3) | ✅ | ✅ | ✅ |
| `yampl` (message passing library, for AthenaMP) | [recipes/yampl](recipes/yampl) | ✅ | ✅ | — |
| `frontier-client` (Frontier database caching client) | [recipes/frontier-client](recipes/frontier-client) | ✅ | ✅ | ✅ |
| `lcg-coral` (LCG relational abstraction layer) | [recipes/lcg-coral](recipes/lcg-coral) | ✅ | ✅ | ✅ |
| `lcg-cool` (LCG conditions database) | [recipes/lcg-cool](recipes/lcg-cool) | ✅ | ✅ | ✅ |
| `crestapi` (CREST conditions database client) | [recipes/crestapi](recipes/crestapi) | ✅ | ✅ | ✅ |
| `chai` (conditions access for CREST and COOL) | [recipes/chai](recipes/chai) | ✅ | ✅ | ✅ |
| `hep-crest-client`, `pycrest-client` (CREST python client, for the trigger configuration) | [recipes/hep-crest-client](recipes/hep-crest-client), [recipes/pycrest-client](recipes/pycrest-client) | ✅ | ✅ | ✅ |
| `tdaq-common` (event format, event storage, error reporting) | [recipes/tdaq-common](recipes/tdaq-common) | ✅ | ✅ | ✅ |
| `tdaq-dqm-core` (tdaq-common's data quality monitoring framework, for the data quality algorithms) | [recipes/tdaq-dqm-core](recipes/tdaq-dqm-core) | ✅ | ✅ | ✅ |
| `atlas-gaudi` (Gaudi, ATLAS's fork v40r4.002) | [recipes/atlas-gaudi](recipes/atlas-gaudi) | ✅ | ✅ | ✅ |
| `athena-externals` (the base project: AtlasCMake, AtlasLCG, find modules) | [recipes/athena-externals](recipes/athena-externals) | ✅ | ✅ | ✅ |
| `geomodel-core`, `geomodel-tools` (GeoModel 6.29.0, detector geometry toolkit) | [recipes/geomodel](recipes/geomodel) | ✅ | ✅ | ✅ |
| `atlas-acts` (ACTS 47.7.0 with the plugins ATLAS uses) | [recipes/atlas-acts](recipes/atlas-acts) | ✅ | ✅ | ✅ |
| `atlas-geant4` (ATLAS's Geant4 10.6.3 fork with VecGeom 1.1.21, as AthenaExternals builds them) | [recipes/atlas-geant4](recipes/atlas-geant4) | ✅ | ✅ | ✅ |
| `atlas-rivet` (conda-forge's Rivet 4.1.4 recipe, on FastJet 3.5.1 build 5) | [recipes/atlas-rivet](recipes/atlas-rivet) | ✅ | ✅ | ✅ |
| `athena-core` (framework, StoreGate, configuration, POOL I/O, conditions, ByteStream) | [recipes/athena-core](recipes/athena-core) | ✅ | ✅ | ✅ |
| `athena-detdescr` (identifiers, GeoModel geometry, ACTS geometry, magnetic field) | [recipes/athena-detdescr](recipes/athena-detdescr) | ✅ | ✅ | ✅ |
| `athena-edm` (xAOD and trigger event data model: AOD/DAOD I/O) | [recipes/athena-edm](recipes/athena-edm) | ✅ | ✅ | ✅ |
| `athena-edm-det` (detector event data: HITS/RDO/ESD I/O) | [recipes/athena-edm-det](recipes/athena-edm-det) | ✅ | ✅ | ✅ |
| `athena-analysis` (CP tools and algorithms, trigger decision tool) | [recipes/athena-analysis](recipes/athena-analysis) | ✅ | ✅ | ✅ |
| `athena-reco-tracking` (inner detector and ITk tracking, vertexing) | [recipes/athena-reco-tracking](recipes/athena-reco-tracking) | ✅ | ✅ | ✅ |
| `athena-reco` (full reconstruction, `Reco_tf.py`, digitization) | [recipes/athena-reco](recipes/athena-reco) | ✅ | ✅ | · |
| `athena-trigger` (L1 simulation, High-Level Trigger) | [recipes/athena-trigger](recipes/athena-trigger) | ✅ | ✅ | · |
| `athena-sim` (Geant4 simulation, ISF, generator interfaces, `Sim_tf.py`) | [recipes/athena-sim](recipes/athena-sim) | ✅ | ✅ | · |
| `athena-rest` (the project `Athena`: derivations, data quality, event display, the rest) | [recipes/athena-rest](recipes/athena-rest) | ✅ | ✅ | · |
| `athena` (all the layers) | [recipes/athena](recipes/athena) | ✅ | · | · |
| `athena-devel` (compilers and externals for building Athena packages against the release) | [recipes/athena-devel](recipes/athena-devel) | ✅ | · | · |
| `clhep` (existing feedstock: built without `-fvisibility-inlines-hidden`, ATLAS's RandGaussZiggurat fix) | [athena-notes/feedstock-changes/clhep](athena-notes/feedstock-changes/clhep) | ✅ | ✅ | ✅ |

✅ = builds locally with rattler-build and passes the recipe tests: linux-aarch64 natively in
Docker on an Apple-silicon Mac, linux-64 in Docker under Rosetta (conda-forge's CI image),
osx-arm64 natively. · = not done yet. — = not available on that platform.

All recipes are version 25.0.73 of the Athena release or the version of the external that
AthenaExternals 25.0.73 uses. Only python 3.13 is built locally.

**What works**

- **`athena.py` runs from a plain conda environment.** `athena-core` (179 packages, 34 MB)
  runs ATLAS's HelloWorld job, serial and multi-threaded, and its output matches ATLAS's
  reference log for the test:

  ```sh
  athena.py AthExHelloWorld/HelloWorldConfig.py
  athena.py --threads=2 AthExHelloWorld/HelloWorldConfig.py
  ```

- **Conditions from SQLite through POOL and COOL**: ATLAS's IOVDbTestAlg write job puts
  conditions payloads in a POOL file and registers them in a COOL SQLite database, and the read
  job reads them back through IOVDbSvc. The output matches ATLAS's reference logs except for
  three framework debug lines.
- **Raw data**: an EventStorage file of random events is written with tdaq-common's eformat,
  then listed and copied with Athena's `AtlListBSEvents` and `AtlCopyBSEvent`.
- **The ATLAS geometry builds and agrees with ATLAS's release.** With `athena-detdescr` (219
  packages, 39 MB), DumpGeo builds every subdetector's GeoModel description for
  `ATLAS-R3S-2021-03-02-00` and writes it to a GeoModel SQLite file:

  ```sh
  python -m DumpGeo.DumpGeoConfig --outFilename=geometry.db
  ```

  The result has the same counts as ATLAS's own release (58,181 PhysVols, 26,226 FullPhysVols,
  59,048 LogVols, 485 materials), and GeoModel's `gmcat` reads it back unchanged. The geometry
  comes from ATLAS's geometry database through Frontier, so this needs network and CVMFS
  (conditions payloads). Identifiers are decoded from the release's ID dictionaries, without
  either.
- **xAOD files are read and written without CVMFS.** With `athena-edm` (187 packages, 49 MB),
  Athena reads an [ATLAS Open Data](https://opendata.cern.ch) DAOD_PHYSLITE file (2015 data,
  CC0), dumps every object in it, and writes a copy with all its event data and metadata, which
  it reads back. Both dumps (127,173 lines) are **identical to the dump ATLAS's release
  writes**. PyROOT reads both files through `xAOD::MakeTransientTree`, element links included:

  ```python
  import ROOT
  f = ROOT.TFile.Open("DAOD_PHYSLITE.37001701._000001.pool.root.1")
  tree = ROOT.xAOD.MakeTransientTree(f)
  for i in range(tree.GetEntries()):
      tree.GetEntry(i)
      print([e.pt() for e in tree.AnalysisElectrons])
  ```

  With CVMFS, 38 of ATLAS's T/P converter tests (AODs written by releases 15 to 21) pass too.
- **HITS, RDO and ESD files.** With `athena-edm-det` (137 packages, 23 MB), Athena reads ATLAS's
  Run 3 test files (sim hits, raw data, calorimeter cells, prepared data, tracks), dumps every
  object and writes copies; all six dumps are **identical to ATLAS's release**. The layer's 364
  compiled T/P round-trip unit tests pass at build time. These jobs need CVMFS (ATLAS's test
  files and conditions).
- **Physics analysis of ATLAS Open Data with the CP tools, without CVMFS.** `athena-analysis`
  (169 packages, 76 MB) runs ATLAS's CP algorithms on the Open Data file: good-runs list,
  calibrated and selected muons, electrons, photons, taus, small- and large-R jets with flavour
  tagging, tracks, missing transverse momentum, overlap removal, and trigger decisions and
  matching:

  ```sh
  CPRun.py -i DAOD_PHYSLITE.37001701._000001.pool.root.1 -t opendata_data15.yaml -o opendata
  ```

  The n-tuple (116 events, 80 branches) is **identical to the one ATLAS's release writes**.
  Without CVMFS, the calibration files (44 MB of GroupData) are downloaded from ATLAS's web
  server by PathResolver, which `athena-core`'s activation enables, and the geometry database
  is read through Frontier. With CVMFS, two of ATLAS's own CP algorithm tests also pass: the
  full-simulation one (150 events, every systematic variation, 5,130 branches, identical to
  ATLAS's) and the multi-threaded PHYSLITE one. 78 of ATLAS's unit tests pass at build time.
- **Reconstruction gives the same results as ATLAS's release.** `athena-reco-tracking` (241
  packages, 63 MB) runs ATLAS's inner detector tracking job on its Run 3 RDO test file:
  clusters, space points, track finding and fitting, TRT extension, track particles and
  primary vertices, **identical** to ATLAS's (419k lines of dumped objects). `athena-reco` (324
  packages, 110 MB) runs the full reconstruction with ATLAS's transform:

  ```sh
  Reco_tf.py --CA --inputRDOFile RDO.pool.root --outputESDFile ESD.pool.root \
    --outputAODFile AOD.pool.root --maxEvents 5 \
    --conditionsTag OFLCOND-MC23-SDR-RUN3-11-02 --geometryVersion ATLAS-R3S-2021-03-02-00
  ```

  Calorimeters, inner detector, muons, electrons and photons, jets, taus, particle flow,
  b-tagging and missing transverse energy: the ESD (1.73M lines dumped) and the AOD (406k) are
  **identical to ATLAS's**. These jobs need CVMFS (ATLAS's test files and conditions payloads).
- **The trigger runs as in ATLAS's release.** `athena-trigger` (176 packages, 64 MB) runs the
  High-Level Trigger on simulation as ATLAS's trigger tests do, with its Dev menu, on the same
  RDO file:

  ```sh
  python -m TriggerJobOpts.runHLT --filesInput=RDO.pool.root --evtMax=5 --threads=1 \
    'Trigger.triggerMenuSetup="Dev_pp_run3_v1_TriggerValidation_prescale"' \
    'IOVDb.GlobalTag="OFLCOND-MC23-SDR-RUN3-11-02"' --preInclude Campaigns.MC23a
  ```

  The L1 simulation, then every HLT chain (reconstruction, hypotheses, decisions), with the
  trigger data written to RDO_TRIG. The chain counts table that ATLAS's trigger tests compare
  (111 chains) is **identical to ATLAS's**.
- **The detector simulation runs, close to but not identical to ATLAS's.** `athena-sim` (155
  packages) runs ATLAS's Run 3 Geant4 simulation (FullG4MT_QS, the production simulator) with
  its transform, on ATLAS's ttbar EVNT test file, with Geant4 from ATLAS's own fork
  (`atlas-geant4`):

  ```sh
  Sim_tf.py --CA --simulator FullG4MT_QS --inputEVNTFile EVNT.pool.root \
    --outputHITSFile HITS.pool.root --maxEvents 3 \
    --conditionsTag default:OFLCOND-MC23-SDR-RUN3-11-02 \
    --geometryVersion default:ATLAS-R3S-2021-03-02-00 \
    --preInclude EVNTtoHITS:Campaigns.MC23eSimulationMultipleIoV
  ```

  The input to Geant4 (the generator record after the beam spot smearing) is **identical** to
  ATLAS's, and every subdetector has its hits in the same amounts (the large collections within
  10% over the 3 events), but the showers are not identical: see the known issues. The job needs
  CVMFS (the test file, conditions payloads, and ATLAS's ReleaseData for the LAr high-voltage
  maps).
- **Derivations are identical to ATLAS's.** `athena-rest` (149 packages, 55 MB), the ATLAS
  project named `Athena` like ATLAS's top project, has everything else: the derivation framework,
  data quality, the VP1 event display, validation, test beam. It makes DAOD_PHYS and
  DAOD_PHYSLITE, the formats most analyses use, from ATLAS's Run 3 ttbar AOD test file with
  ATLAS's transform:

  ```sh
  Derivation_tf.py --inputAODFile AOD.pool.root --outputDAODFile test.pool.root \
    --formats PHYS PHYSLITE --maxEvents 10
  ```

  Both outputs (104k and 31k lines dumped) are **identical to ATLAS's**. This needs CVMFS (the
  test file and conditions payloads).
- **All of Athena in one package, and a developer workflow on top of it.** `athena` installs
  every layer; its environment runs `athena.py` with all ten projects set up, the top one named
  `Athena` as in ATLAS's release. `athena-devel` adds the compilers (the gcc major the layers
  were built with), CMake and the development packages of the externals, so that ATLAS's usual
  work area builds against the installed release, as with `asetup` on CVMFS:

  ```sh
  conda install athena-devel
  git atlas init-workdir https://gitlab.cern.ch/atlas/athena.git   # or any sparse checkout
  git atlas addpkg AthExHelloWorld
  cmake -S athena/Projects/WorkDir -B build && cmake --build build
  source build/*/setup.sh
  athena.py AthExHelloWorld/HelloWorldConfig.py   # runs the work area's copy
  ```

  The recipe's test does this with a changed HelloWorld tool, whose new message `athena.py`
  then prints.
- **Every component has its configurable.** Each layer's test checks the Gaudi configuration
  databases against the component lists, because a crash in `genconf` drops a component silently
  without failing the build (this is how the Gaudi ABI problem showed up).

## Where this stands

**Ten Athena layers build and pass their tests on linux-aarch64.** They hold 1,936 of the
release's 1,966 packages (as `layers.py` counts them): about 14.7k of its 14.9k translation units,
or **99% of the build**. The other 30 need externals that no conda package provides (see the
known issues). That is enough to run Athena jobs, build the geometry, read and write every ATLAS
data format, simulate events with Geant4, reconstruct RDO into ESD and AOD with `Reco_tf.py`, run
the trigger, make derivations, and analyse DAOD_PHYS and DAOD_PHYSLITE with the CP tools.

| Layer | Packages | CPU-h | Max RSS per compile | Jobs on 7 GB | Recipe here (`-j10`) | Package |
|---|---|---|---|---|---|---|
| `athena-core` | 179 | ~2.5 | 2.2 GB | 4 | 13 min | 34 MB |
| `athena-detdescr` | 219 | ~4 | 1.9 GB | 4 | 40 min | 39 MB |
| `athena-edm` | 187 | ≤8 | 3.0 GB | 2–3 | 50 min | 49 MB |
| `athena-edm-det` | 137 | ~3 | 2.6 GB | 2–3 | 50 min | 23 MB |
| `athena-analysis` | 169 | ~5 | 3.3 GB | 2 | 38 min | 76 MB |
| `athena-reco-tracking` | 241 | ~6 | 2.7 GB | 2 | 41 min | 63 MB |
| `athena-reco` | 324 | ~9 | 3.0 GB | 2 | 66 min | 110 MB |
| `athena-trigger` | 176 | ~4.5 | 3.0 GB | 2 | 38 min | 64 MB |
| `athena-sim` | 155 | ~2 | 1.8 GB | 3 | 23 min | 323 MB¹ |
| `athena-rest` | 149 | ~3 | 2.5 GB | 2–3 | 27 min | 55 MB |

CPU time and memory are measured with
[compile_cost.py](athena-notes/analysis/scripts/compile_cost.py) from the ninja log of a kept
build tree. Recipe times include the tests. ¹ Mostly the object files of the simulation
packages (640 MB unpacked), which ATLAS's release installs too: AtlasGeant4 is linked from them,
so that a work area can relink it with its own changes.

**Proven so far**

- AtlasCMake runs inside rattler-build against conda-forge's externals with three small patches
  to AtlasCMake/AtlasLCG and a handful of find modules.
- Stacking works: ten Athena projects on AthenaExternals, each built only against the
  installed ones: eleven projects deep, where ATLAS's own release uses three. Dictionaries,
  `genconf`, the CLID database and the python configuration work across projects.
- Jobs give the same results as ATLAS's release, checked object by object, except the Geant4
  simulation (see below).
- Analysis of ATLAS Open Data works without CVMFS (with network).
- Build cost matches `layers.py`'s estimates (2–9 CPU-h per layer), so each layer should fit a
  default conda-forge runner; reco, at about 9 CPU-h on 2 cores, is the tightest.

**Not proven yet** (roughly by risk)

1. **Licences** of CORAL, COOL, CrestApi and yampl (below): nothing that reads conditions can go
   to conda-forge without them, and CORAL is in the core layer.
2. **Runtime data without CVMFS.** The geometry database (even the Open Data analysis needs it,
   to find the LHC period of the file) and the conditions are read through ATLAS's Frontier
   servers, and POOL conditions payloads exist only on CVMFS. Publishing a default
   `FRONTIER_SERVER` needs ATLAS's agreement.
3. **Time and memory on CI.** The heaviest compiles peak at 3.3 GB, so the layers need `-j2` on
   a 7 GB runner: from about 2.5 hours to, for reco, about 4.5 hours of the 6-hour limit.
4. **Simulation identical to ATLAS's.** With ATLAS's own Geant4 fork, the simulation agrees in
   its input and in the amounts of hits, but not hit by hit (known issues).
5. **linux-64 and osx-arm64.** linux-64 should be routine; osx-arm64 needs Gaudi on macOS and an
   unknown amount of libc++ work in code that has never seen macOS.
6. Maintenance: every ROOT/Boost/python migration forces a coordinated rebuild of all layers in
   order, as for CMSSW.

**Known issues / open questions**

- Several dependencies have **no licence** and cannot go to conda-forge until that is resolved
  (each of their recipes has a `LICENSE-STATUS.md`):
  - `lcg-coral` and `lcg-cool`: no licence file and no licence headers (the same open question
    as for the CMS fork of CORAL in the sister project). `lcg-coral` conflicts with that
    `coral` package (same library names).
  - `crestapi`: ATLAS's copyright header without a licence; Apache-2.0 is likely.
  - `yampl`: no licence file and no headers.
  - `hep-crest-client` and `pycrest-client` (the CREST python clients): Apache 2.0 in their
    package metadata, but no licence file.
- **ATLAS's `authentication.xml` is never shipped** (it holds Oracle passwords). AtlasAuthentication
  installs one when it finds it on AFS; the build fails if one is ever installed. One package,
  `PixelConditionsTools`, keeps an `authentication.xml` with credentials in its sources
  (`share/`, in ATLAS's public repository), and the install area carries the packages'
  sources: the layers drop it from the sources they ship. Worth reporting to ATLAS.
  `CORAL_AUTH_PATH` points at a directory without one, which is fine for Frontier and SQLite.
- **Runtime data** (PLAN.md, D6):
  - the geometry database and conditions need `FRONTIER_SERVER`. The tests set ATLAS's public
    server, which answers direct requests (the proxy `asetup` adds answers 403 from outside
    CERN). The geometry databases on CVMFS have no clear licence and are not packaged;
  - POOL conditions payloads exist only on CVMFS (an MC payload package would be about 3.8 GB);
  - ATLAS's test files on CVMFS (`data-art`, `ASG` test files) have no clear licence and are
    only read in place, when CVMFS is mounted. Tests that need no CVMFS use ATLAS Open Data
    (CC0), downloaded as a recipe source;
  - GroupData is downloaded over HTTP when CVMFS is absent. PathResolver used to save an HTTP
    error page as the file and leave empty files after failed downloads (one of ATLAS's two web
    mirrors answers 404 for everything): fixed by core patch 0004 (**upstreamable**).
- **Gaudi is built here** (ATLAS's fork, v40r4.002) rather than taken from conda-forge:
  conda-forge's 40.4 is a gcc 14 build that exports libstdc++'s `std::format` internals, and
  Athena code built with gcc 15 binds to them; `genconf` then crashes for every component with
  a `double` property, and the build does not fail. It also needs the gaudi feedstock's
  plugin-path patch. (conda-forge's gaudi exports `GaudiKernel` with an absolute path to
  `librt.so` in its feedstock's build sysroot: worth reporting there.)
- **Binary prefix replacement can blank string literals.** Packaging rewrites the build prefix
  in binaries in place (a shorter path, padded with NULs), and the linker stores a string
  literal that is the tail of another string inside it. A property name `"c"` ended up at the
  end of `".../AthCommonDataStore.icc"` (a `__FILE__` of a header in the prefix) and was empty
  in the packaged library only, which broke the HLT's b-jet selection. The layers map the
  prefix out of `__FILE__` (`-fmacro-prefix-map`); `-fno-merge-constants` does not work, as
  `arm_neon.h`'s pragmas restore the default (and the linker merges string tails whatever its
  `-O` level). The same happened in the simulation: rootcling writes the dictionary's include
  paths into the library, and `$PREFIX/include/Geant4` swallowed the literal `"Geant4"`, the
  default name of Geant4's random number stream. The stream had no name in the packaged
  library, so its seeds, which are derived from the name, differed from ATLAS's. athena-externals'
  patch 0004 runs rootcling with `--noIncludePaths`, as genreflex already does. This can
  affect any conda package built against headers in its prefix: worth raising with
  conda-forge.
- **CLHEP**: ATLAS uses a fork. AtlasCLHEP_RandomGenerators relies on members that are protected
  only in the fork; core patch 0001 reads them as protected without an ABI change
  (**upstreamable**). The fork's RandGaussZiggurat draws its uniform numbers in double
  precision: in single precision a value just below 1 rounds to 1, the tail algorithm takes
  `log(0)`, and the random sequence of everything sharing the engine (Geant4's, in the
  simulation) changes. conda-forge's build also hides the inline `clone()` functions of
  GenericFunctions (`-fvisibility-inlines-hidden`), so code that calls them does not link. A
  feedstock change ([athena-notes/feedstock-changes/clhep](athena-notes/feedstock-changes/clhep))
  does both: built without the flag, with the fork's double-precision fix as a patch (to be
  proposed to the feedstock and to CLHEP).
- **Eigen 3.4, not 5.** conda-forge's pinning has moved to Eigen 5, which is not API
  compatible with ATLAS's code. geomodel, atlas-acts and the layers build against
  `eigen-abi-devel` 3.4.0, whose run export keeps them from being mixed with Eigen 5 builds.
- **`fastjet-cxx` is pinned to 3.5.1 build 5**, the last one that ships its headers. Since build
  6 they are in `fastjet-cxx-devel`, which needs a `cgal-cpp` that does not exist for both
  Boost 1.90 and Eigen 3.4.
- **The Linux sysroot is glibc 2.34** (EL9's, what ATLAS targets): PerfMonComps uses `mallinfo2`.
  The compilers and python are given to CMake by absolute path, because `root_base` brings its
  own compiler with the 2.17 sysroot into the host prefix.
- **`-fvisibility-inlines-hidden`** (from conda-forge's `CXXFLAGS`) is stripped: ATLAS's
  libraries export inline functions that other libraries link to.
- **Find modules for conda-forge's layouts**, in `athena-externals`: TBB (conflicts with TBB's
  own CMake configuration), CORAL (AtlasLCG's requires the CORAL server, which is not built),
  tdaq-common (no TDAQ environment), FastJet contrib (one `libfastjetcontribfragile` instead of
  a library per contrib) and onnxruntime (headers in `include/onnxruntime/core/session/`).
  Because every ATLAS project installs a copy of its base's find modules and AtlasCMake's own
  modules, changing one means rebuilding every layer.
- **The layers' exported targets named glibc's libraries in the build environment**
  (`libpthread.a` for the ~170 packages that ask ROOT for `pthread`, and `libdl`/`libm` through
  CMake's FindHDF5), a path that exists only during that layer's build. The next layers built
  here only because the old build trees were still on disk; on CI every layer above core would
  have failed. athena-externals' PostConfig now gives those libraries by name, and each layer's
  build fails if its CMake configuration names the build environment.
- **`ROOT_FOUND` was false in every layer**: AtlasLCG's FindROOT looks for ROOT's python
  modules in `<ROOT>/lib`, and conda-forge has them in `site-packages`. Nothing noticed until a
  package required ROOT. The PostConfig now sets `ROOT_PYTHON_PATH`.
- **`clid.db` lacked types of lower layers**: AtlasCMake builds it from the component
  libraries, so a type is listed only if some component uses it, often a reconstruction or
  trigger component in a later layer. The layers also run `genCLIDDB` on their POOL converter
  libraries.
- **`athena.py` is a `#!/bin/sh` script with bash arrays**, which fails where `/bin/sh` is dash
  (Debian, Ubuntu). Core patch 0003 makes it `#!/bin/bash` (**upstreamable**).
- **GeoModel flags in core-only jobs**: every IOVDb job reads a GeoModel flag whose module lives
  in a later layer. Core patch 0002 guards the import (**upstreamable**); core-only conditions
  jobs must set `GeoModel.Run` explicitly.
- **Triton is not on conda-forge**: FlavorTagInference builds its Triton inference service only
  where the client is found (analysis patch 0001, **upstreamable**). It is off by default, and
  the ONNX path is unchanged.
- **onnxruntime prints a warning** where it cannot tell the CPU's vendor (containers,
  emulation), which breaks ATLAS's reference comparisons; the analysis layer's unit tests ignore
  it.
- `frontier-client` had no `run_exports`, so CORAL's Frontier plugin could not load it (the
  CMSSW project's copy of the recipe has the same gap).
- **GitLab's archive endpoint sometimes returns an empty 200 response** for the 58 MB athena
  tarball, which fails the sha256 check. Locally the source cache is seeded by hand; in CI a
  mirror may be needed.
- **30 packages are not packaged** (174 of the release's 14.9k translation units), because they
  need externals that no conda package provides (`layers.py`'s "none"):
  - the generators that conda-forge does not have (Herwig, Sherpa, EvtGen with Photos++ and
    Tauola++, Hijing, Starlight, EPOS, SuperChic, ...). Pythia8, LHAPDF and Rivet are there, and
    the generator control packages without compiled code are packaged;
  - the GPU and FPGA code (CUDA, vecmem, traccc, detray, SYCL, Xilinx HLS types) and the Triton
    client;
  - the online packages: the full TDAQ release, tdaq-common's data flow interface
    (`df_ef_interface`, no licence file) and webdaq (athenaHLT's services, the HLT's bytestream
    service, the data flow emulator), and the ITk pixel decoder (`itksw-endec`).
  dqm_core, the part of tdaq-common that data quality needs, is its own recipe
  (`tdaq-dqm-core`), as it needs ROOT.
- **Oracle's client is not on conda-forge** (it is proprietary). Only DQUtils requires it, and
  does not use it: rest patch 0001 drops it (**upstreamable**). Athena reaches Oracle databases through
  CORAL's Oracle backend, which `lcg-coral` does not build either: jobs read conditions through
  Frontier or SQLite, and the tools that open ATLAS's Oracle databases directly do not work.
- **The simulation is not identical to ATLAS's release.** Same Geant4 fork, patches and
  options (multithreaded, static, VecGeom, link-time optimization), same CLHEP fix, same
  inputs and random seeds: the generator record and the first Geant4 steps agree, then the
  showers diverge after a few vertices. Ruled out: the C library (the packaged layer in an EL9
  container gives the same output), the memory allocator, the Geant4 data sets, VecGeom's
  configuration, link-time optimization and CLHEP. Left: the compiler (conda-forge's gcc 15.3
  against LCG's 15.2; their LTO objects cannot be mixed, LCG's are zstd-compressed) and the
  builds of the other externals. Geant4 also raises floating point exceptions (INVALID,
  DIVBYZERO) in every event here and none in ATLAS's release; aarch64 has no floating point
  traps, so ATLAS's FPE auditor only reports them per algorithm, and no single subdetector
  causes them. The test therefore checks the generator record exactly and each detector's hits
  within 20%. To be looked at with ATLAS's simulation experts, and on linux-64.
- **Geant4 is ATLAS's fork** (10.6.3 with ATLAS's patches, PLAN.md D5), not conda-forge's
  geant4 11.x, so that the simulation can be compared with the release: `atlas-geant4`
  conflicts with conda-forge's geant4 and vecgeom. The data sets are conda-forge's
  `geant4-data-*` packages in the 10.6 versions. `athena-sim`'s activation sets `G4VERS`
  (ATLAS's simulation configuration checks it) from the installed Geant4.
- **Rivet is rebuilt** (`atlas-rivet`, conda-forge's recipe and patches): conda-forge's rivet
  needs `fastjet-cxx-devel`, see the FastJet entry above.
- **ReleaseData exists only on CVMFS** (no clear licence): the simulation reads the LAr
  high-voltage maps from it. ATLAS's `setup.sh` sets `SITEROOT` to `/afs` by default; the
  activation of `athena-sim` and `athena-rest` points it at CVMFS when CVMFS is mounted and the
  directory set does not exist. (It checks the directory, not whether the variable is set:
  conda runs the activation scripts alphabetically, and the first layer's `setup.sh` sets it.)
- **Work areas compile against glibc 2.17's headers**, though the layers were built with 2.34:
  `root_base` requires the 2.17 sysroot (for cling), and an environment has only one. Code that
  needs newer glibc functions does not compile in a work area, and executables that link layer
  libraries do not link (`undefined reference to dlopen@GLIBC_2.34`: the 2.17 stubs lack the
  layers' symbol versions) without `-Wl,--allow-shlib-undefined`. Components, which is what
  work areas mostly build, are not affected. `athena-devel` could add the flag in its
  activation.
- **`athena.py` calls `which`**, which minimal EL9 images do not have: a run requirement of
  `athena-core`.
- **chai's headers** are in `include/chai/`, as in the TDAQ release's externals (atlasexternals
  installs them one level deeper): some packages find chai as a tdaq-common component.
- **CaloRecGPU** installs nothing without CUDA, its configuration flags included, which the
  trigger's calorimeter configuration reads anyway: reco patch 0001 installs its python
  modules without CUDA (**upstreamable**).
- The job transforms need `psutil`, `ps` (procps) and `prmon` at run time, and the trigger
  configuration the CREST python client: run requirements of `athena-core` and
  `athena-trigger`.
- The activation scripts still source ATLAS's `setup.sh` (provisional): plain activation
  scripts are planned (D6).
- The install areas carry the packages' sources (`src/`), as on CVMFS; to be weighed against
  package size.
- **macOS (osx-arm64)** needs a handful of things that Linux does not (details in PLAN.md, M8):
  - Libraries find each other through rpaths: dyld ignores `LD_LIBRARY_PATH`, and System
    Integrity Protection drops `DYLD_LIBRARY_PATH` from every script started through a system
    shell or `/usr/bin/env` (`athena.py` among them). AtlasCMake sets rpaths (athena-externals
    patch 0005), `setup.sh` also fills `GAUDI_PLUGIN_PATH` and `ROOT_LIBRARY_PATH` there, and
    the libraries that load plugins by bare name (CORAL, ers, EventStorage, Gaudi's python)
    look them up through their rpaths or the environment's prefix.
  - conda-forge's python has the interpreter built in, so a library that links libpython runs
    against a second, uninitialised copy of it inside python (macOS binds symbols per library).
    Gaudi's and Athena's libraries look Python's symbols up in the process instead, and every
    executable loads libpython.
  - Clang 20, the compiler of conda-forge's ROOT 6.40 there, with `-D_LIBCPP_DISABLE_AVAILABILITY`:
    conda-forge's libc++ 20 headers mark `std::from_chars` with an attribute that does not
    compile (to be reported to conda-forge). AtlasCMake builds C++23 with it (ATLAS switches at
    clang 22), as ROOT is a C++23 build.
  - **ROOT's interpreter only works with the macOS 11.0 SDK**: conda-forge's ROOT 6.40 ships C++
    modules built against it, and with newer SDKs (13.3 to 27) cling fails on the mach headers
    that `boost/thread` includes. The local builds use that SDK (`CONDA_BUILD_SYSROOT`), and
    users would need it in `SDKROOT`: to be reported to conda-forge's root feedstock.
  - Athena needed about twenty small source changes for libc++ and macOS (athena-core patches
    0005 and 0006: missing includes, C++20 removals that libstdc++ keeps, `<malloc.h>`,
    `prctl`, `fenv_t` on Apple silicon, `std::vector<bool>`'s proxy, ...). yampl (AthenaMP's
    event service) and valgrind are Linux only, and the packages that need them are left out
    or built without them (`packages_excluded_osx.txt` per layer).
  - Copies of system binaries are killed on current macOS: AtlasCMake's private copy of
    `/bin/bash` (now a link to conda-forge's bash), and the copy of `/usr/bin/env` that CORAL
    and COOL install (removed).
  - Every project's `cmake/modules/` has both `FindNumPy.cmake` and `Findnumpy.cmake`, and
    AtlasLCG's `FindVDT.cmake` hides ROOT's `FindVdt.cmake` on the case-insensitive file
    system: athena-externals defines the `VDT::VDT` target that ROOT looks for.
  - **ROOT 6.40.04 rather than 6.40.02** (Linux keeps ATLAS's 6.40.02): 6.40.02's
    `TTreeIndex` rounds 64-bit keys to the precision of `long double`, which on Apple silicon
    is a plain `double`, so POOL could not find the entries of files whose `index_ref`
    values are beyond 2^53 (most of ATLAS's MC files: "duplicate key", then "POOL read
    failed"). ROOT fixed it in 6.40.04, which conda-forge has.
  - Clang compiles a `dynamic_cast` to a `final` class as a comparison with the address of its
    vtable, but on macOS a class without a key function (all its virtual functions inline) has
    a private copy of its vtable in every library that uses it, so the cast fails for objects
    made in another library (POOL's converters could not write RDOs). Athena (through
    athena-externals' CMake configuration) and Gaudi are built with
    `-fno-assume-unique-vtables` on macOS.
  - macOS's math library rounds some results differently from glibc's: athena-edm-det's T/P
    converter tests accept, on macOS only, numbers that differ from ATLAS's reference in their
    last printed digit (one number in one test so far).
  - The FPE auditor reports floating point exceptions that are not Athena's: conda-forge
    builds ROOT with clang, which evaluates some guarded divisions anyway and then discards
    them (`TVector3::PseudoRapidity` of a null vector divides 0 by 0, e.g. in the tau T/P
    converter). The tests check the logs for FPE warnings only on Linux. ROOT's macOS build
    would need `-ffp-exception-behavior=maytrap` (ATLAS adds `strict` to a few of its own
    libraries with clang): to be reported to conda-forge's root feedstock.
  - The rootmaps name libraries with a `.so` suffix; AtlasCMake links dictionary libraries to
    that name but not the libraries with a built-in dictionary (RootUtils): the layers' build
    scripts add the missing links.
  - With libc++, AtlasSTLAddReflexDict's rootmap also lists the `pair<>`s of some maps that
    xAODCoreSTLDict lists, and ROOT warns about each in every job: the layers keep the first
    entry of each class, the one ROOT uses.
  - ATLAS's test scripts take GNU's sed, diff and grep for granted (`post.sh`, which compares
    test logs with references): athena-core requires them from conda-forge there.
  - The CP algorithms declare the `eventNumber` n-tuple branch as `unsigned long`, but
    `EventInfo`'s is a `uint64_t`, which is `unsigned long long` there: analysis patch 0002
    declares it `uint64` (**upstreamable**).
  - Three unit tests' references depend on libstdc++ (`std::shuffle`'s order, the text of an
    exception): the layers skip them on macOS (`unit_tests_excluded_osx.txt`).
- **ATLAS's scripts start with `#!/usr/bin/bash` or `#!/bin/env`** (233 in the sources), which
  neither macOS nor distributions without the merged `/usr` have: the layers rewrite them to
  `#!/usr/bin/env` before building.
- **SelectionHelpers' expression lexer reads a destroyed object** after it is moved (its tokenizer
  keeps iterators into the moved-from string). It works by chance with libstdc++ and not with
  libc++, whose strings keep more characters inline: analysis patch 0003 (**upstreamable**).
- **The silicon seed finders found no seeds on macOS.** Their space points and seeds are in
  `std::list`s with ATLAS's `ArenaPoolSTLAllocator`, whose copies do not share its pool (by
  design), while libc++'s `std::list` allocates each node through a temporary copy of its
  allocator: the node was freed with the copy, and the next one reused its memory. The job ran
  without errors and found almost no tracks. Analysis patch 0002 uses `std::allocator` for these
  lists under libc++ (**upstreamable**; the allocator does not meet the standard's requirement
  that copies can free each other's memory). It is the only `std::list` with that allocator in
  Athena; its maps, sets and hash tables are not affected (libc++ allocates their nodes through
  the container's own allocator).
- **The tests' references are per platform**: ATLAS's own release writes different floating point
  numbers on x86_64 and aarch64 (dumps of ESD, AOD, derivations, tracking, CP n-tuples; the
  DAOD reading and trigger counts agree). The linux-64 references come from ATLAS's x86_64
  release, run under Rosetta here. There is no ATLAS release for macOS: there the dumps are
  compared only in size, every collection within 5% of its size in ATLAS's release
  (`dump_counts.py`, on every platform). On linux-64 the reco and rest dumps of these builds differ from
  ATLAS's x86_64 release in a few numbers (by one unit in the last printed digit, and the
  derivations in 7 electrons' `UEcorr_Pt`, where they have the values of ATLAS's aarch64
  release): their sums are listed with ATLAS's.
- Under Rosetta, ATLAS's x86_64 release itself reports floating point exceptions (e.g. in the
  muon geometry's initialisation), which it does not on aarch64, and which ATLAS's own FPE
  checks on x86_64 machines would catch: most likely an emulation artifact (not checked on
  real x86_64 hardware). It fails the tests' FPE log checks locally.

## Roadmap

1. **M8:** linux-64, and osx-arm64 (Gaudi on macOS, AtlasCMake Apple fixes, libc++ fixes).
2. **M9:** submit the external recipes, upstream the patches (AtlasCMake/AtlasLCG to
   atlasexternals, Athena's to athena, GeoModel's split to its feedstock), and hand off.
3. Ask ATLAS (pure lead time): licences for CORAL, COOL, CrestApi, the CREST python clients
   and yampl; the credentials in `PixelConditionsTools`' sources; a default
   `FRONTIER_SERVER` for anonymous users; the geometry database and POOL conditions payloads
   without CVMFS; why the simulation differs (with ATLAS's simulation experts).

See [PLAN.md](PLAN.md) for details.

## Repository layout

- [PLAN.md](PLAN.md): analysis, decisions, milestones and progress log.
- [recipes/](recipes): the recipes. The upstream staged-recipes `example-*` recipes are also here.
  Each Athena layer has its `packages.txt` (from `layers.py`), its project `CMakeLists.txt`,
  activation scripts, patches and tests.
- [athena-notes/research](athena-notes/research): background research: the build system, every
  external against conda-forge, the package graph, prior art, and runtime data and platforms.
- [athena-notes/analysis/scripts](athena-notes/analysis/scripts): scripts (python3, stdlib only)
  that read the release on CVMFS:
  - `depgraph.py`, `cmakeparse.py`, `graph.py`: every package's CMakeLists.txt evaluated into
    targets, sources and link edges;
  - `includes.py`, `pyimports.py`: dependencies the link graph does not show (`#include`s and
    python imports);
  - `layers.py`: partitions Athena into deliverable-driven layers and checks their closure and
    cost (`--list <layer>` gives a layer's packages);
  - `cfgdeps.py`, `cfgmap.py`: the python packages and component types a job configuration
    uses, run in ATLAS's release, and the packages and layers they map to;
  - `compile_cost.py`: CPU time and peak memory of a layer's compile jobs;
  - `tpcnv_tests.py`: the T/P converter tests of a layer's packages;
  - `stats.py`, `heavy.py`, `projects.py`: size, heavy externals and ATLAS's own projects.
- [athena-notes/spike](athena-notes/spike): the M1 spike that showed Athena projects stack in a
  conda prefix (superseded by the recipes).
- [athena-notes/build-local.sh](athena-notes/build-local.sh): builds the recipes inside a
  container.
- [athena-notes/cvmfs-athena.sh](athena-notes/cvmfs-athena.sh): runs a command in ATLAS's own
  release from CVMFS, the reference for the tests.
- [CLAUDE.md](CLAUDE.md): notes for AI coding agents working on this repository.

## Building locally

The recipes use the [rattler-build](https://rattler.build) v1 format. On an Apple-silicon Mac
they are built natively for linux-aarch64 in a `condaforge/miniforge3` container, with the
repository at `/repo` and a volume at `/work`:

```sh
docker run -d --name athena-dev -v "$PWD":/repo -v athena-work:/work \
  -v /cvmfs:/cvmfs:ro condaforge/miniforge3 sleep infinity   # /cvmfs is optional
docker exec athena-dev bash -c '
  mamba create -y -p /work/tools -c conda-forge rattler-build conda-forge-pinning
  cp /work/tools/conda_build_config.yaml /work/'
docker exec athena-dev bash -c 'export PATH=/work/tools/bin:$PATH; cd /repo &&
  ./athena-notes/build-local.sh linux_aarch64 [recipes/<name> ...]'
```

With no recipes, `build-local.sh` builds the externals in dependency order; the Athena layers
are given explicitly (`recipes/athena-core recipes/athena-detdescr ...`). Built packages end up
in `/work/output`, which is used as a local channel, and logs in `/work/logs`. `KEEP_BUILD=1`
keeps the build directories, for `compile_cost.py` or to rerun parts of a build. With `/cvmfs`
mounted, the tests that need ATLAS's test files run too; without it they are skipped.

The reference outputs come from ATLAS's own release on CVMFS, run in an `almalinux:9` container
with [cvmfs-athena.sh](athena-notes/cvmfs-athena.sh); see [CLAUDE.md](CLAUDE.md) for the
details of both containers.
