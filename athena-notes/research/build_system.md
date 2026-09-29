# Athena's build system (AtlasCMake) and how to run it inside rattler-build

Reference: Athena 25.0.73 (`release/25.0.73`), installed at
`/cvmfs/atlas.cern.ch/repo/sw/software/25.0/Athena/25.0.73/InstallArea/aarch64-el9-gcc15-opt`
(called `$IA` below). Its externals project is at
`/cvmfs/atlas.cern.ch/repo/sw/software/25.0/AthenaExternals/25.0.73/InstallArea/aarch64-el9-gcc15-opt`
(`$EA`).

Sources used (all under `_work/`, which is git-ignored):
- `_work/atlasexternals`: a `--depth 1` clone of `atlas/atlasexternals` at tag `2.1.91`. It holds `Build/AtlasCMake`,
  `Build/AtlasLCG`, `Projects/*Externals` and `External/*`.
- `_work/athena-Projects/Projects/*` and `_work/athena-Projects/Build/AtlasBuildScripts/*`: fetched file by file from
  GitLab raw at `release/25.0.73`. The installed `src/` has no `Projects/` directory.
- `_work/Gaudi-v40r4.002`: the ATLAS Gaudi fork tarball.
- `_work/cmakelists.json`: every package `CMakeLists.txt` of the release, made by another agent.

**Legend:** **[V]** means verified by reading the code or files cited. **[I]** means inferred or a guess that still
needs a build to confirm.

---

## 1. AtlasCMake: where it lives, which version, what it does

### 1.1 Location and version

- **[V]** AtlasCMake and AtlasLCG are part of `atlasexternals`, not of `athena`. `Projects/Athena/externals.txt` has
  `AthenaExternalsVersion = 2.1.91`.
  - Byte-identical to the modules installed in `$IA/cmake/modules/` (checked with `diff -q`):
    `AtlasFunctions.cmake`, `AtlasInternals.cmake`, `AtlasLibraryFunctions.cmake`,
    `AtlasDictionaryFunctions.cmake`, `LCGFunctions.cmake`, `FindROOT.cmake`.
  - `AtlasCMakeConfig-version.cmake` says `1.0.0`. The real version is the atlasexternals tag.
- **[V]** Every installed project carries a full copy of AtlasCMake, AtlasLCG and the extra find modules in
  `<InstallArea>/cmake/modules/` (292 entries in `$IA`).
  - `atlas_project()` installs AtlasCMake's own directory (`AtlasFunctions.cmake` around lines 170-190).
  - `LCGConfig.cmake` installs the AtlasLCG modules (`install( DIRECTORY .../modules DESTINATION cmake )`).
  - The `External/*` packages install their own `Find*.cmake`: Gaudi, Acts, GeoModel, Geant4, VecMem, lwtnn,
    onnxruntime, dSFMT, yampl, APTypes, BAT, KLFitter, APE, NumPy.
  - A downstream project gets all of AtlasCMake just from `find_package(<BaseProject>)`. The config file prepends
    `<base>/cmake/modules` to `CMAKE_MODULE_PATH` and does `include(AtlasFunctions)`.
- **[V]** Other versions pinned by `Projects/Athena/build_externals.sh`:
  - `LCG_VERSION_NUMBER=110`, `LCG_VERSION_POSTFIX=_ATLAS_5`;
  - Gaudi `atlas/Gaudi v40r4.002`;
  - Acts `v47.7.0` (with traccc);
  - GeoModel `6.29.0`;
  - VecMem `1.27.0`;
  - `ATLAS_GEANT4_USE_LTO=TRUE`, `ATLAS_VECGEOM_USE_LTO=TRUE`, `ATLAS_GAUDI_USE_CUDA=TRUE`.

  `$IA/ReleaseData` records GCC 15.2.0, CMake 4.4.0 and CUDA 13.3.
- **[V]** The C++ standard is 23. `PreConfig.cmake.in` sets `CMAKE_CXX_STANDARD 23`, and
  `atlas_set_compiler_defaults()` picks 23 for GCC ≥ 15 or Clang ≥ 22.

### 1.2 The main functions

These are in `atlasexternals/Build/AtlasCMake/modules/`. The usage counts are over the 1,966 package `CMakeLists.txt`
files of 25.0.73 (`_work/cmakelists.json`).

| Function | Calls / packages | What it does |
|---|---|---|
| `atlas_subdir(Name)` (`AtlasFunctions.cmake:602`) | 1966 | Declares the package and a `Package_<Name>` target. It **installs the whole package source directory into `src/<path>`**, and those installed sources double as the public headers (see §2.4). The name must equal the leaf directory. |
| `atlas_add_library` (`AtlasLibraryFunctions.cmake:46`) | 1206 / 1135 | Shared (or static or object) library. With `PUBLIC_HEADERS X` it creates `include/X -> ../src/<pkg>/X` symlinks at install time. Exported as `<Project>::<lib>` into `<Project>Config-targets.cmake`. |
| `atlas_add_component` (`:321`) | 1037 / 1009 | MODULE library linked to `Gaudi::GaudiPluginService`, then three build-time steps: `listcomponents` → `.components`, `genconf` → `<lib>Conf.py` + `.confdb` + `.confdb2_part`, and `genCLIDDB` → `<lib>_clid.db` unless `NOCLIDDB`. Legacy configurables are on by default (`ATLAS_BUILD_LEGACY_CONFIGURABLES`). Without Gaudi it builds `.asgcomponents` with `asg_component_factory_scanner`. |
| `atlas_add_dictionary` / `atlas_generate_reflex_dictionary` (`AtlasDictionaryFunctions.cmake:30,595`) | 477 / 424 | Runs `genreflex ... --noIncludePaths --rootmap --library`, producing `<dict>ReflexDict.cxx`, `.dsomap` and `_rdict.pcm`. Headers are found at runtime through `ROOT_INCLUDE_PATH`. |
| `atlas_add_root_dictionary` (`:403`) | 19 | `rootcling`. |
| `atlas_add_poolcnv_library`, `atlas_add_tpcnv_library`, `atlas_add_sercnv_library` | 102, 45, 17 | POOL/T-P converter libraries, generated from skeletons with `configure_file`. They are components, so the same genconf/listcomponents steps apply. |
| `atlas_add_xaod_smart_pointer_dicts` (from `xAODCore/cmake/xAODUtilitiesConfig.cmake`) | 39 | Generated xAOD dictionaries. Found through `xAODUtilities_DIR`. |
| `atlas_add_executable` | 210 / 109 | |
| `atlas_add_test` | 1646 / 528 | Compiled tests are built by default (`ATLAS_ALWAYS_BUILD_TESTS=ON`, `AtlasFunctions.cmake`). |
| `atlas_install_python_modules` (`AtlasInstallFunctions.cmake:344`) | 780 / 776 | Copies to `python/<pkg>/`, runs `pyCompile.py` (a syntax check with `compile()`, no `.pyc`), and optionally a checker as `POST_BUILD_CMD`. 778 packages pass `POST_BUILD_CMD ${ATLAS_FLAKE8}` (`flake8_atlas`). |
| `atlas_install_joboptions`, `_data`, `_runtime`, `_xmls`, `_scripts`, `_docs` | 120, 82, 84, 10, 267, 1 | Install to `jobOptions/<pkg>`, `data/<pkg>`, `share/` (flat), `XML/<pkg>`, `bin/`. |
| `atlas_generate_cliddb` (`AtlasLibraryFunctions.cmake:873`) | 20 (+ every component) | `genCLIDDB -p <lib> -o <lib>_clid.db`. Skipped when Gaudi is not found. |
| `atlas_generate_componentslist` (`:811`) | internal | `Gaudi::listcomponents --output lib<lib>.components lib<lib>.so`. |
| `atlas_merge_project_files` (`AtlasInternals.cmake:870`) | internal | Merges the per-library files into project files (list below). |

`atlas_merge_project_files` writes these project-level files:
- `lib/<Project>.rootmap`
- `lib/<Project>.components`
- `lib/<Project>.confdb`
- `lib/<Project>.confdb2`, via `mergeConfdb2.py`
- **`share/clid.db`**, whose name does not depend on the project, via `mergeClids.sh`

In `$IA/lib` these are `Athena.components`, `Athena.confdb`, `Athena.confdb2`, `Athena.rootmap` (plus
`libHepMC3rootIO.rootmap`), next to 2,478 `.so` and 483 `_rdict.pcm` files. `$EA/lib` has `Gaudi.components`,
`Gaudi.confdb`, `Gaudi.confdb2` and `GaudiDict.rootmap`.

### 1.3 What the build executes

This matters for cross-compilation and for macOS. Nearly all of it goes through
`<build>/CMakeFiles/atlas_build_run.sh` (`scripts/atlas_build_run.sh.in`). That script sources the build area's
`setup.sh` and then `exec`s the command. `atlas_project()` wraps **every link command** with it (it rewrites
`CMAKE_CXX_CREATE_SHARED_LIBRARY` and the others) so that private dependencies resolve through `LD_LIBRARY_PATH`.

**[V]** These steps run freshly built target-architecture code or target-architecture host tools:
1. `Gaudi::listcomponents` on every component library (1,037). It `dlopen`s the library and all its dependencies.
2. `Gaudi::genconf` on every component library. It `dlopen`s the library, **instantiates every
   algorithm/tool/service** to read its default properties, and writes Python configurables.
3. `genCLIDDB` (built in `Control/CLIDComps`) on every component library and on the 20 explicit
   `atlas_generate_cliddb` libraries. It loads the library.
4. `genreflex`/`rootcling` from ROOT for about 535 dictionaries (477 + 19 + 39).
5. Python run through `atlas_build_run.sh`:
   - `pyCompile.py` (776 packages);
   - `flake8_atlas` (778 packages, if found);
   - `mergeConfdb2.py`;
   - package-specific generators: `Trigger/TrigT1/L1Common` (a Python generator from an XML schema) and
     `Tools/PyUtils` (`apydep.py` scans the whole source tree for `packages.py.dot`).
6. Package-specific executables that the release itself builds:
   - `TrigConfL1TopoGenPyAlg` and `TrigConfL1TopoGenPyHardware`, in `L1TopoAlgorithms` and `L1TopoHardware`;
   - `han-config-gen` (DataQualityInterfaces), which `DataQualityConfigurations` uses to compile the
     `.hcfg` files;
   - `protoc` in `EventIndexProducer` (a build tool);
   - `python -m nanobind --cmake_dir` in `ColumnarToolWrapperPython`.
7. Optional analysers: cppcheck (`ATLAS_USE_CPPCHECK` is ON in `Projects/Athena/CMakeLists.txt`, but it is only a
   warning when cppcheck is missing), and the GCC checker plugin (`ATLAS_USE_GCC_CHECKERS=ON`, active only if
   `libchecker_gccplugins` from AthenaExternals is found).

**Consequence:** as with CMSSW, a cross-compiled build (for example osx-arm64 on an osx-64 runner) cannot run
items 1-3 and 6. It needs native runners, or those steps turned off and done later (not practical: Python
configuration depends on the configurables). linux-64, linux-aarch64 and native osx-arm64 builds are fine.

---

## 2. The project model and building on top of an installed release

### 2.1 Projects at this tag

**[V]** `Projects/` contains AnalysisBase, AthAnalysis, AthGeneration, AthSimulation, Athena, ColumnarAnalysis,
DetCommon, VP1Light and WorkDir (from the GitLab tree API). There is no AthDerivation or AthenaP1 any more, although
`WorkDir/CMakeLists.txt` still lists them as possible parents.

| Project | Base (`atlas_project(USE ...)`) | Packages in the 2026-09-28 main nightly | Notes |
|---|---|---|---|
| Athena | AthenaExternals | 1964 (1966 in 25.0.73) | `package_filters.txt` only excludes about 12 analysis/Intel packages |
| AthSimulation | AthSimulationExternals | 375 | compiled with `-DSIMULATIONBASE` |
| AthAnalysis | AthAnalysisExternals | 345 | `-DXAOD_ANALYSIS` |
| AthGeneration | AthGenerationExternals | 222 | `-DGENERATIONBASE` |
| AnalysisBase | AnalysisBaseExternals (LCG **0**) | 229 | no Gaudi (`XAOD_STANDALONE`); builds its own ROOT, Python, Boost and so on when they are missing |
| ColumnarAnalysis | AnalysisBaseExternals | 228 | |
| DetCommon | none (AtlasCMake from an atlasexternals checkout, LCG 110 "externals" only) | 18 | proof that a project can sit directly on AtlasCMake + LCG with no externals project |
| VP1Light | VP1LightExternals | | README has (2019) macOS build instructions |
| WorkDir | `${ATLAS_PROJECT}` (any of the above, default Athena) | user-selected | the "developer area" |

**[V] Important:** the subset projects are **not** subsets of the Athena build. They compile shared packages with
different preprocessor definitions (`add_definitions(-DSIMULATIONBASE)` and others in the project `CMakeLists.txt`;
`XAOD_STANDALONE` in 239 package `CMakeLists.txt`, `XAOD_ANALYSIS` in 86, `SIMULATIONBASE` in 64, `GENERATIONBASE`
in 48). Layers of a conda "full Athena" must be built in plain Athena mode. AthAnalysis, AthSimulation and
AthGeneration could only be separate, parallel conda products.

### 2.2 How a project is built on a base

**[V]** From `AtlasFunctions.cmake:57-600` (`atlas_project`) and `skeletons/ProjectConfig.cmake.in`:
1. The project `CMakeLists.txt` does `find_package(<Base>)`, which pulls in AtlasCMake from `<base>/cmake/modules`.
   It then calls `atlas_project(USE <Base> <version> PROJECT_ROOT ../../)`.
2. `atlas_project` globs every `CMakeLists.txt` under `PROJECT_ROOT`, filters them with `ATLAS_PACKAGE_FILTER_FILE`
   (default `${CMAKE_SOURCE_DIR}/package_filters.txt`), and `add_subdirectory`s the selected ones. Filter rules are
   `+ regex` / `- regex` on the package path, first match wins, and no rules means everything
   (`AtlasInternals.cmake:937`).
3. After the packages it calls `find_package(<Base> <ver> COMPONENTS INCLUDE)`. The base's config then "deep copies"
   every `Base::X` imported target to a plain-named `X` (`atlas_copy_target`, `AtlasInternals.cmake:1189`), **unless a
   target `X` already exists**. That is how a locally rebuilt package shadows the release's copy. Package
   `CMakeLists.txt` refer to targets by plain name (`LINK_LIBRARIES AthContainers`).
4. It installs `<Project>Config.cmake`, `-version.cmake` (`SameMinorVersion`) and `-targets*.cmake`, plus
   `setup.sh`, `packages.txt`, `compilers.txt` and `ReleaseData`.
   - The config file records `<Project>_BASE_PROJECTS` (for example `AthenaExternals;25.0.73`).
   - When found, it **recursively** runs `find_package(<base> <ver> EXACT)` for each of them, and on `INCLUDE` it
     copies the targets of the whole chain, nearest project first (`$IA/cmake/AthenaConfig.cmake`, lines 55-205).
   - It also includes the optional `cmake/PreConfig.cmake` and `cmake/PostConfig.cmake` for project-specific
     propagation. Athena's `PreConfig` sets C++23, CUDA architectures, flake8, cppcheck, LCG and the externals
     `find_package`s. Its `PostConfig` does `find_package(Gaudi REQUIRED)`.
5. **Stacking depth.** The mechanism is recursive and imposes no depth limit.
   - **[V]** WorkDir → Athena → AthenaExternals (three levels) is the normal daily workflow.
   - **[V]** The exported targets of a project name its base projects' targets by their plain copied names. The
     25.0.73 Athena exports 525 references to `Gaudi::GaudiKernel`, and references to AthenaExternals libraries
     rewritten to relative paths. So a project built on a project that was itself built on a base resolves correctly.
   - **[I]** `lcg_generate_env` still skips a hard-coded list `AtlasCore AtlasConditions AtlasEvent
     AtlasReconstruction AtlasTrigger AtlasAnalysis AtlasSimulation AtlasOffline AtlasHLT AtlasProduction ...`
     (`LCGFunctions.cmake` around line 638). This looks like a leftover from the early CMake era, when the offline
     release was built as a deep stack of projects, so deep stacking was a design goal. No current ATLAS build uses
     more than three levels, so a spike must confirm it.

### 2.3 WorkDir, the developer area

**[V]** `Projects/WorkDir/CMakeLists.txt` is ATLAS's "build a few packages against an installed release" project:
- **Picking the parent.** `ATLAS_PROJECT` (a cache variable) defaults to the first of `Athena AthenaP1 AnalysisBase
  ...` whose `$ENV{<P>_DIR}` is set. It then does `find_package(${ATLAS_PROJECT} REQUIRED)` and
  `project(WorkDir VERSION ${<parent>_VERSION})`.
- **Sources.** It takes `CxxUtilsSettings`, `AthenaPoolUtilitiesTest_DIR`, `xAODUtilities_DIR` and
  `AtlasGeant4Utilities_DIR` from the source tree if the package is checked out, and otherwise from
  `$ENV{<parent>_DIR}/src/...` or the parent's installed `cmake/`. **So the installed `src/` is required downstream.**
- **Build type.** It **forces** `CMAKE_BUILD_TYPE` from `Release` to `RelWithDebInfo`. `-DCMAKE_BUILD_TYPE=Release`
  is overridden, and only another capitalisation such as `RELEASE` survives.
- **Other settings.** `ATLAS_ALWAYS_CHECK_WILDCARDS=TRUE`, `compile_commands.json`, and
  `atlas_project(USE ${ATLAS_PROJECT} ${ver})`.
- **No Pre/PostConfig.** It does not generate or install them. That is fine for a leaf, because the parent chain's
  are pulled in recursively.
- **The runtime environment of the base release comes from outside.** The user has run `asetup`, which sources the
  release `setup.sh`.
  - The build area's `setup.sh` only prepends the WorkDir's own directories.
  - Its `setup_baseprojects` looks for `${DIR}/../../../../<base>/<ver>/InstallArea/<plat>/setup.sh`, which exists
    only in the CVMFS layout, and silently skips it otherwise.
  - So when `genconf` runs for a WorkDir package, the base release's `lib/` is on `LD_LIBRARY_PATH` only because of
    the environment the build started in.

**Answer to "can layer N be a project on top of layers 1..N-1 in the same prefix?"** **[V]/[I]** Yes, and this is
closer to ATLAS's intended use than the CMSSW case was:
- Each layer can be its own named project (for example `AthenaCore`, then `AthenaEvent` on it, ...), built with
  `atlas_project(USE <previous layer> 25.0.73)` and a package filter file.
- Every layer finds the whole chain through `find_package(<previous layer>)` and the recursion above.
- Several base projects can be listed (`USE A 1.0 B 1.0`), but a linear chain is enough.
- Naming the **last** layer `Athena` would make `find_package(Athena)` and a user's
  `cmake athena/Projects/WorkDir` behave exactly as on CVMFS.
- The layer project `CMakeLists.txt` should be written by us. Take Athena's for the setup and propagation logic, and
  WorkDir's for "source-or-installed" handling of the helper modules. Do not use `Projects/WorkDir` unchanged: it
  forces RelWithDebInfo and installs no Pre/PostConfig.

### 2.4 Install area layout and relocatability

**[V]** Layout of `$IA` (top-level entries):
- `bin/`: 2,215 files.
- `lib/`: 2.9 GB. `.so` files, `_rdict.pcm` files and the project-merged files.
- `python/<pkg>/`: 1,197 packages.
- `include/<X>`: 1,061 **relative symlinks into `../src/<path>/<X>`**.
- `src/<path>/`: 329 MB. The complete package directories: headers, `.cxx`, `cmake/`, `share/`.
- `share/`: flat, 580 entries, including `clid.db`.
- `data/<pkg>/`, `jobOptions/<pkg>/`, `XML/<pkg>/`, `doc/`.
- `cmake/`: `AthenaConfig*.cmake`, `PreConfig.cmake`, `PostConfig.cmake`, `LCGConfig*.cmake`, per-package helpers
  (`xAODUtilitiesConfig.cmake`, `AthenaPoolUtilitiesTestConfig.cmake`, `AtlasGeant4UtilitiesConfig.cmake`),
  and `modules/`.
- Top-level files: `setup.sh`, `env_setup.sh`, `packages.txt`, `packages.dot`, `packages.py.dot`, `compilers.txt`,
  `ReleaseData`, `README.txt`, `LICENSE.txt`, `objects-Release`.

Imported library targets point their `INTERFACE_INCLUDE_DIRECTORIES` at **`${_IMPORT_PREFIX}/src/<path>`**, not at
`include/` (for example `Athena::xAODCore`). The installed sources are therefore the headers of the release.

Relocatability:
- **[V]** The config files use `PACKAGE_PREFIX_DIR` and `_IMPORT_PREFIX`, both relative. `setup.sh` resolves
  itself, and the `include/` symlinks are relative.
- **[V]** References to externals are written as `${LCG_RELEASE_BASE}/...` (`_lcg_make_paths_relocatable`), 705 of
  them in `AthenaConfig-targets.cmake`.
- **[V]** AthenaExternals paths are rewritten to `${Athena_INSTALL_DIR}/../../../../AthenaExternals/${ver}/InstallArea/${plat}/`
  by `cmake/modules/skeletons/atlas_export_sanitizer.cmake.in`, which comes from AthenaExternals. This hard-codes the
  CVMFS sibling layout `<root>/<Project>/<version>/InstallArea/<platform>`, and only for AthenaExternals. The same
  script also makes missing imported files a warning instead of a fatal error.
- **[V] No RPATHs at all.** `atlas_project` sets `CMAKE_SKIP_RPATH`, `CMAKE_SKIP_BUILD_RPATH` and
  `CMAKE_SKIP_INSTALL_RPATH` ON. Everything relies on `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH`. The release is
  "relocatable" because it depends on the environment.
- **[I]** Under conda, absolute `$PREFIX` paths written into the targets files, `env_setup.sh` and similar are
  handled by rattler-build's text prefix replacement. Libraries must get proper RPATHs, or an `LD_LIBRARY_PATH`
  activation (see §7).

---

## 3. How externals are found (LCG, AtlasLCG, Gaudi)

### 3.1 AtlasLCG

**[V]** `Build/AtlasLCG/LCGConfig.cmake` and `LCGConfig-version.cmake` handle `find_package(LCG <N>)`:
- The release directory is `${LCG_RELEASE_BASE}/LCG_<N><postfix>`. The default base is
  `/cvmfs/sft.cern.ch/lcg/releases`, which the `LCG_RELEASE_BASE` or `LCG_NIGHTLY` environment variables override.
- It reads `LCG_externals_<platform>.txt` and `LCG_generators_<platform>.txt` and sets `<NAME>_LCGROOT` for each
  package. The platform string comes from `/etc/os-release` and the compiler (for example
  `aarch64-el9-gcc15-opt`), or from `$ENV{LCG_PLATFORM}`.
- It appends a selection of those roots to `$ENV{CMAKE_PREFIX_PATH}`.
- It prepends its `modules/` directory, 170+ `Find<X>.cmake` files, to `CMAKE_MODULE_PATH`.

The find modules use `lcg_external_module`, `lcg_python_external_module` and `lcg_wrap_find_module`
(`modules/LCGFunctions.cmake`). **When `<NAME>_LCGROOT` is set** they search only there, and add `/usr/...` to
`CMAKE_SYSTEM_IGNORE_PATH` plus `NO_SYSTEM_ENVIRONMENT_PATH NO_CMAKE_SYSTEM_PATH`. **When it is not set** they are
ordinary `find_path` / `find_library` / `find_program` calls, which honour `CMAKE_PREFIX_PATH`. Several modules
(`FindROOT`, `FindActs`, `FindGeant4`, `FindGaudi`, `Findnlohmann_json`, `FindTBB`, ...) first try the upstream
CONFIG package.

**[V] The "no LCG" mode exists and is used:**
- `find_package(LCG 0)` prints "Using the LCG modules without setting up a release" (`LCGConfig-version.cmake`).
  `LCGConfig.cmake` then skips the whole release setup (`if( NOT LCG_VERSION EQUAL 0 )`), and
  `lcg_need_rpm` returns early.
- AnalysisBaseExternals uses this by default: `set( LCG_VERSION_NUMBER 0 CACHE STRING ...)` in
  `Projects/AnalysisBaseExternals/CMakeLists.txt`.
- Its `ProjectOptions` pick `ATLAS_BUILD_{PYTHON,BOOST,ROOT,TBB,XROOTD,DAVIX,...}` depending on whether the external
  is found on the system.
- Both externals projects already expose the relevant switch as a cache variable: `LCG_VERSION_NUMBER` in
  AthenaExternals (and DetCommon). Pointing everything at a conda prefix is therefore:

  ```
  -DLCG_VERSION_NUMBER=0 -DLCG_VERSION_POSTFIX= -DCMAKE_PREFIX_PATH=$PREFIX
  ```

**[V] Small patch needed:**
- AthenaExternals' `CMakeLists.txt` and its installed `PostConfig.cmake.in`, Athena's `PreConfig.cmake.in` and
  DetCommon's `CMakeLists.txt` all call `find_package(LCG <N> REQUIRED EXACT)`.
- For `N=0`, `LCGConfig-version.cmake` sets `PACKAGE_VERSION_EXACT FALSE`, so `EXACT` makes the find fail. This
  follows from CMake's documented semantics; it has not been run.
- The fix is to set `PACKAGE_VERSION_EXACT TRUE` in the version-0 branch (one line), or to drop `EXACT`.

**[V] What stays hard-wired even with LCG 0:**
- **tdaq and tdaq-common.** `Findtdaq-common.cmake` (in AtlasCMake) uses
  `atlas_external_module(... INCLUDE_SUFFIXES installed/include LIBRARY_SUFFIXES installed/${TDAQ_PLATFORM}/lib)`
  under `TDAQ-COMMON_ATROOT = $ENV{TDAQ_RELEASE_BASE}/tdaq-common/tdaq-common-14-00-00`. A conda `tdaq-common`
  would need either that directory shape or a patched find module. `atlas_external_module` uses
  `NO_CMAKE_SYSTEM_PATH` but still honours `CMAKE_PREFIX_PATH`.
- **Hard-coded `/cvmfs`, `/afs`, `/eos` and `http` data paths** end up in `env_setup.sh`: DATAPATH, CALIBPATH,
  LHAPATH, `SITEROOT=/afs/cern.ch`, G4 data. They come from package `*EnvironmentConfig.cmake` files (§4) and are
  only environment, so they can be overridden in activation.
- **`OpenGL_GL_PREFERENCE LEGACY`** is set in AthenaExternals' PreConfig. It is harmless.

### 3.2 AthenaExternals and Gaudi

**[V]** Gaudi is **not** a separate project any more. It is `External/Gaudi` inside AthenaExternals
(`Projects/AthenaExternals/package_filters.txt`):
- It is an `ExternalProject_Add` of `atlas/Gaudi v40r4.002`, installed into the AthenaExternals install area.
- It installs `lib/cmake/Gaudi/GaudiConfig.cmake` (upstream Gaudi CMake) and ATLAS's
  `cmake/modules/FindGaudi.cmake`.
- `FindGaudi.cmake` sets `GAUDI_NO_TOOLBOX TRUE`, so AtlasCMake does the configurables and components instead of
  Gaudi's own CMake functions. It also sets helper cache variables for TBB, AIDA, HepPDT, CppUnit and unwind, and
  calls `find_package(Gaudi CONFIG)`.
- AtlasCMake needs only the imported targets `Gaudi::GaudiPluginService`, `Gaudi::genconf`,
  `Gaudi::listcomponents` and `Gaudi::GaudiKernel`, plus `GAUDI_*` path variables.
- **[I]** So any Gaudi install that provides `GaudiConfig.cmake` works: a separate conda `gaudi` package built from
  the ATLAS fork, or a Gaudi built inside an "athena-externals" layer. The ATLAS patches in v40r4.002 against
  upstream v40 still have to be checked (externals topic).

AthenaExternals also builds (`package_filters.txt`): Acts (+traccc/detray/vecmem), APTypes, boost-mpi3,
CheckerGccPlugins, CLHEP (`ATLAS_BUILD_CLHEP` defaults to ON), Coin3D, SoQt, Simage, COOL/CORAL (their
`ATLAS_BUILD_*` default to OFF, so they are taken from LCG), flake8_atlas, GPerfTools, Geant4, VecCore, VecGeom,
GeoModel, GoogleTest, lwtnn, MKL, onnxruntime, prmon, PyModules, dSFMT, triSYCL, itksw-endec, hgtd-decoder, yampl,
nlohmann_json and Triton.

**[V]** The installed `AthenaExternalsConfig.cmake` is what gives Athena its AtlasCMake modules, its
`LCGConfig.cmake` and its `Find*` modules. Its `PostConfig` redoes `find_package(LCG <N> EXACT)`.

**Implication:** a conda "layer 0" can be:
- **(a)** the real AthenaExternals project built with LCG 0 and a package filter reduced to what conda-forge lacks.
  It installs the Config file, modules and PostConfig, plus the reduced externals.
- **(b)** Everything in separate conda packages, plus an AthenaExternals **built with `- .*` as its only filter**,
  which yields just the CMake shell (Config, modules, `LCGConfig`, Pre/PostConfig, `env_setup.sh`). The `Find*.cmake`
  files that come from `External/*` (Gaudi, Acts, GeoModel, Geant4, ...) must then be added to its `cmake/modules/`
  by hand.

Option (b) keeps Athena's own `CMakeLists.txt` unchanged: `find_package(AthenaExternals)` and
`atlas_project(USE AthenaExternals ...)` keep working.

---

## 4. The runtime environment

**[V]** Sources of the environment for a release:
1. **`setup.sh`** (`AtlasCMake/modules/scripts/setup.sh.in`), per project:
   - It sources the base projects' `setup.sh` in "extonly" and then "relonly" mode, through the CVMFS-relative
     path, then its own `env_setup.sh`.
   - It then prepends:
     - `CMAKE_PREFIX_PATH=<IA>`
     - `PATH=<IA>/bin:<IA>/share`
     - `LD_LIBRARY_PATH` and `DYLD_LIBRARY_PATH=<IA>/lib`
     - `PYTHONPATH=<IA>/python:<IA>/lib`
     - `JOBOPTSEARCHPATH=<IA>/jobOptions`
     - `DATAPATH=<IA>/data:<IA>/share`
     - `CALIBPATH=<IA>/data:<IA>/share`
     - `ROOT_INCLUDE_PATH=<IA>/include`
     - `XMLPATH=<IA>/XML`
   - Finally it prepends `.` to `JOBOPTSEARCHPATH`.
2. **`env_setup.sh`**, generated by `lcg_generate_env` from every `find_package`d external's `<X>_PYTHON_PATH`,
   `_BINARY_PATH`, `_LIBRARY_DIRS`, `_INCLUDE_DIRS` and `_ENVIRONMENT`, and from package
   `<Pkg>EnvironmentConfig.cmake` files. The Athena one sets (names from `grep export`):
   - LCG and external paths in PATH, LD_LIBRARY_PATH, PYTHONPATH and ROOT_INCLUDE_PATH, `ROOTSYS`, and
     **`PYTHONHOME=${TDAQ_PYTHON_HOME}`**, which must not be carried over;
   - `GAUDI_PROPERTY_PARSING_ERROR_DEFAULT_POLICY=Exception`, `CLING_STANDARD_PCH=none`, `OPENBLAS_NUM_THREADS=1`,
     `ORA_FPU_PRECISION`, `COOL_DISABLE_CORALCONNECTIONPOOLCLEANUP=YES`;
   - `CORAL_AUTH_PATH` and `CORAL_DBLOOKUP_PATH=${Athena_DIR}/XML/AtlasAuthentication`;
   - `UBSAN_OPTIONS`, `VALGRIND_*`;
   - `DATAPATH` extras: AthenaExternals `share`, `/sw/DbData`, `${ATLAS_RELEASEDATA}/v20` with
     `SITEROOT=/afs/cern.ch`, the TwissFiles, `/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art`;
   - `CALIBPATH` extras: `/cvmfs/atlas.cern.ch/repo/sw/database/GroupData`, eos, and the http GroupData mirrors;
   - LHAPDF (`LHAPATH`, `LHAPDF_DATA_PATH`), the G4 data variables (`G4*DATA`, `G4PATH`), generator versions and
     paths (`PYTHIA8*`, `HERWIG7*`, `SHERPA*`, `MADPATH`, `EVTGEN*`, ...);
   - `TDAQ_*`, `QT_PLUGIN_PATH`, `VP1PLUGINPATH=${Athena_DIR}/lib`;
   - `ASG_TEST_FILE_*` (test inputs on CVMFS).

   The package-level sources are `Tools/PathResolver/PathResolverEnvironmentConfig.cmake`,
   `Control/AthenaCommon/AthenaCommonEnvironmentConfig.cmake`,
   `Database/ConnectionManagement/AtlasAuthentication/...EnvironmentConfig.cmake.in`,
   `External/AtlasDataArea/...`, `Generators/*_i/*EnvironmentConfig.cmake` and others (listed from
   `_work/srcfiles.txt`).
3. **`asetup`** (`/cvmfs/atlas.cern.ch/repo/sw/AtlasSetup/python/AtlConfiguration.py`) mostly locates the release
   and sources `setup.sh`. It also keeps or sets site-level `FRONTIER_SERVER`, `ATLAS_POOLCOND_PATH` and
   `DBRELEASE_OVERRIDE` (lines 432-443). Conditions and database access is a runtime topic for another report.

**[V] How the runtime finds things:**
- **Gaudi components (`.components`) and new-style configurables (`.confdb2`):**
  - `GaudiPluginService/src/PluginServiceV2.cpp:143-146` searches `GAUDI_PLUGIN_PATH`, then `LD_LIBRARY_PATH`, or
    `DYLD_LIBRARY_PATH` on Apple, for every `*.components` file.
  - `dlopen` by leaf name is re-implemented over `GAUDI_PLUGIN_PATH` (line 283 onwards).
  - `GaudiConfiguration/python/GaudiConfig2/_db.py:27-40` globs `*.confdb2` over the same variables.
  - **No patch is needed. Set `GAUDI_PLUGIN_PATH`**, which is not stripped by SIP on macOS. Several `.components`
    and `.confdb2` files per directory are fine.
- **Legacy `.confdb`:** `Control/AthenaCommon/python/ConfigurableDb.py:144` scans **only `LD_LIBRARY_PATH`**. It needs
  a patch for macOS/conda (also read `GAUDI_PLUGIN_PATH`), or an `LD_LIBRARY_PATH` in activation on Linux.
- **CLID DB:** `ClassIDSvc` (`Control/CLIDComps/src/ClassIDSvc.cxx:277-310`) resolves each name in `CLIDDBFiles` with
  `find_all` over `DATAPATH`, so every `clid.db` found is loaded. `MainServicesConfig.py:370` sets
  `CLIDDBFiles=['clid.db','Gaudi_clid.db']`.
- **ROOT dictionaries:**
  - Rootmaps are found by ROOT in its dynamic path: the ROOT libdir plus `LD_LIBRARY_PATH`, or `ROOT_LIBRARY_PATH`
    (the CMSSW conda packaging already relies on `ROOT_LIBRARY_PATH`).
  - Headers are found through `ROOT_INCLUDE_PATH`, because the dictionaries use `--noIncludePaths`. `include/` holds
    symlinks into `src/`.
- **Python** modules come from `<IA>/python` and extension modules from `<IA>/lib` (`PYTHONPATH`). A `.pth` file can
  do this under conda.
- **Job options, data, calibration and XML files** are resolved by PathResolver / `FindFile` over
  `JOBOPTSEARCHPATH`, `DATAPATH`, `CALIBPATH` and `XMLPATH`.

**A conda activation script per layer** must therefore set at least:
- prepend to `PATH` (`bin`, `share`), `PYTHONPATH` (`python`, `lib`, or a `.pth`), `GAUDI_PLUGIN_PATH` (`lib`),
  `ROOT_LIBRARY_PATH` (`lib`), `ROOT_INCLUDE_PATH` (`include`), `JOBOPTSEARCHPATH` (`jobOptions`), `DATAPATH` and
  `CALIBPATH` (`data`, `share`), and `XMLPATH` (`XML`);
- `LD_LIBRARY_PATH` too, unless the legacy-confdb patch and RPATHs make it unnecessary;
- once, in the first layer: `CORAL_AUTH_PATH`, `CORAL_DBLOOKUP_PATH`, `GAUDI_PROPERTY_PARSING_ERROR_DEFAULT_POLICY`,
  `CLING_STANDARD_PCH=none` and `OPENBLAS_NUM_THREADS=1`, plus the external data paths (the CVMFS GroupData/data-art
  locations, which only resolve where CVMFS or HTTP is available);
- nothing of `PYTHONHOME`, `ROOTSYS`, `SITEROOT`, `LCG_*` or `TDAQ_*`.

**[I]** rattler-build activates the host environment for the build script. The **same activation scripts therefore
provide layers 1..N-1 at build time**, which `genconf` needs (see the WorkDir note in §2.3).

---

## 5. macOS and clang

- **[V] AtlasCMake still has Darwin support.**
  - `APPLE` branches: the mac platform id via `sw_vers` (`AtlasInternals.cmake:183`); cores via `sysctl`; CPack
    TGZ instead of RPM; `.so` symlinks for dictionary libraries because rootmaps want `.so`
    (`AtlasDictionaryFunctions.cmake:360`); `-Wl,--no-as-needed` guarded by `NOT APPLE`; `-isysroot` for the
    dependency files.
  - **A private copy of `bash` goes into the build area on macOS**, so that SIP does not strip `DYLD_*`
    (`AtlasFunctions.cmake:560`, `AtlasTestFunctions.cmake:268`).
  - `setup.sh` exports `DYLD_LIBRARY_PATH`, and `build_project.sh` collects `*.dmg`.
  - AnalysisBaseExternals `ProjectOptions` has `APPLE` cases (LibXml2, Davix).
  - VP1Light's README documents macOS builds (`x86_64-mac1014-clang100-opt`, 2019).
  - Core C++ has `__APPLE__`/`__MACH__` guards in 22 files under `Control/` (CxxUtils `clock`, `SealSignal`,
    `excepts`, `sincosf`, `BasicTypes`, AthenaKernel `AthDsoUtils`, AthenaServices `CoreDumpSvc`,
    `FPEControlSvc`, DataModelAthenaPool ...).
  - Gaudi's PluginService and GaudiConfig2 have Apple branches.
- **[V] No current macOS CI.** `/cvmfs/atlas-nightlies.cern.ch/repo/sw/` has no mac platform.
- **[V] Clang is actively built on Linux.** There are `main_Athena_x86_64-el9-clang{16,17,19,22}-opt` nightlies.
  - The clang22 one (2026-09-28, release 25.0.74) builds 1,964 packages, the full Athena, with Clang 22.1.8 and
    gfortran 15.
  - Its compiler lives at `/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase/x86_64/Clang/22.1.8-x86_64-el9-gcc15-opt`,
    so it uses **libstdc++**. libc++ and ld64 remain untested territory, as they were for CMSSW.
- **[V] AtlasCMake problems for conda-forge's macOS toolchain** (`AtlasCompilerSettings.cmake`):
  - For `CMAKE_CXX_COMPILER_ID` `GNU` **or `Clang`**, it unconditionally adds `-Wl,--as-needed`,
    `-Wl,--no-undefined`, `-Wl,--hash-style=both` and `-Wl,-z,max-page-size`, whatever the platform.
  - conda-forge's macOS clang is LLVM clang (ID `Clang`, not `AppleClang`), so ld64 will reject these flags.
  - A small patch guarding them with `NOT APPLE` is needed, plus `atlas_disable_as_needed` in 20 packages.
- **[I]** With `CMAKE_SKIP_RPATH ON`, CMake gives dylibs a bare install name (no `@rpath/`). They load only through
  `DYLD_LIBRARY_PATH`, which SIP strips, and the `/bin/sh` that ninja uses also strips it before
  `atlas_build_run.sh`. For macOS, patch `atlas_project` so RPATH handling can be turned back on
  (`CMAKE_INSTALL_NAME_DIR=@rpath` with install RPATHs), and rely on `GAUDI_PLUGIN_PATH` and `ROOT_LIBRARY_PATH`
  for plugin discovery. This is the same shape as the CMSSW fix (`CMSSW_PLUGIN_PATH`).
- **[V]** Component and MODULE libraries get `CMAKE_SHARED_MODULE_SUFFIX`, which is `.so` on macOS. Shared libraries
  are `.dylib`. Gaudi's `listcomponents` and `genconf` take the file name, and the code already handles both.

---

## 6. Options that reduce scope or cost

**[V]** Cache options and switches:

| Switch | Default | Recommended here | Effect |
|---|---|---|---|
| `ATLAS_ALWAYS_BUILD_TESTS` | ON | OFF | Unit tests (1,646 `atlas_add_test`) go to the non-default `atlas_tests` target. |
| `ATLAS_PACKAGE_FILTER_FILE` | `<proj>/package_filters.txt` | one per layer | Package selection (`+`/`-` regex, first match wins). |
| `ATLAS_USE_CPPCHECK` | ON (Athena project) | OFF | cppcheck wrapper on every TU. |
| `ATLAS_USE_GCC_CHECKERS` | ON | OFF | ATLAS GCC plugin (thread-safety checkers); only active if the plugin library is found. |
| `ATLAS_FLAKE8` / `ATLAS_PYTHON_CHECKER` | `flake8_atlas ...` | pass empty values, or ship `flake8_atlas` | Python checker as a post-build command. If the program is missing, `_atlas_create_post_build_cmd` only warns. |
| `ATLAS_ALLOW_PYTHON_ERRORS` | OFF | OFF | Makes `pyCompile` failures non-fatal. |
| `ATLAS_BUILD_LEGACY_CONFIGURABLES` | TRUE | TRUE for now | `conf,conf2` versus `conf2` only. Turning it off saves `*Conf.py` and `.confdb` but breaks legacy job options. |
| `ATLAS_GEANT4_USE_LTO` | ON (derived from `check_ipo_supported`) | OFF | LTO of AtlasGeant4 and its OBJECT libraries (referenced in 100 package `CMakeLists.txt`); memory-heavy. |
| CUDA / HIP / SYCL | `check_language()` auto-detection (12 CUDA and 4 HIP references in packages, 2 `enable_language(SYCL)`) | keep `nvcc`/`hipcc` out of the build env; pass `-DCMAKE_CUDA_COMPILER=` / `-DCMAKE_HIP_COMPILER=` if needed | Packages guard CUDA code with `if(CMAKE_CUDA_COMPILER)`. `ATLAS_GAUDI_USE_CUDA` only affects AthenaExternals. |
| `ATLAS_ALWAYS_CHECK_WILDCARDS` | FALSE (TRUE in WorkDir) | FALSE | `CONFIGURE_DEPENDS` on globs. There is **no `ATLAS_ALWAYS_CHECK_WILDIMPORTS`** option; the closest name is this one. |
| `ATLAS_FORCE_PLATFORM` | from `/etc/os-release` + compiler | fixed string | The platform directory name inside the build area, and `TDAQ_PLATFORM`. |
| `CMAKE_BUILD_TYPE` | Release (`-DNDEBUG -O2`, forced into `CMAKE_CXX_FLAGS_RELEASE`) | Release | RelWithDebInfo also detaches debug info with objcopy (`atlas_detach_debug_info`). |
| generator | build scripts support Ninja (`-k0`) and make | Ninja | Ninja also enables dictionary depfiles (`ATLAS_DICT_USE_DEPFILE`). |

---

## 7. Implications for conda-forge packaging

### 7.1 Recommended structure

1. **Layer 0, `athena-externals`.**
   - Build atlasexternals' `Projects/AthenaExternals` with `-DLCG_VERSION_NUMBER=0 -DLCG_VERSION_POSTFIX=`,
     `CMAKE_PREFIX_PATH=$PREFIX`, the `EXACT` patch, and a package filter limited to what conda-forge cannot
     provide. Possibly nothing: Gaudi, GeoModel, Acts, CLHEP and the rest as separate feedstocks.
   - This yields `AthenaExternalsConfig.cmake`, `cmake/modules` (AtlasCMake + AtlasLCG + the `External/*` find
     modules, patched), and Pre/PostConfig, in an install area.
   - With it, Athena's own project files work unchanged.
2. **Layers 1..N.**
   - Each layer is a separate recipe and feedstock: a CMake project named after the layer (for example
     `AthenaCore`), with our own `CMakeLists.txt` derived from `Projects/Athena` and `Projects/WorkDir`.
   - `project(<Layer> VERSION 25.0.73)`, then `find_package(<Layer-1>)`, then
     `atlas_project(USE <Layer-1> 25.0.73 PROJECT_ROOT <athena src>)`.
   - Pass `-DATLAS_PACKAGE_FILTER_FILE=<layer>/packages.txt`.
   - Point `CxxUtilsSettings_DIR`, `xAODUtilities_DIR`, `AthenaPoolUtilitiesTest_DIR` and
     `AtlasGeant4Utilities_DIR` at the installed copies when those packages belong to a lower layer, as WorkDir does.
   - Install a `PreConfig`/`PostConfig` in layer 1 only; later layers inherit through the recursion.
   - **The top layer is named `Athena`**, so that `find_package(Athena)` and users' `Projects/WorkDir` work
     unchanged. The chain of `BASE_PROJECTS` gives every layer's targets.
3. **Where to install.** Two options, **[I]** and to be decided with a spike:
   - **(A) One install area per layer**, in the CVMFS shape: `$PREFIX/<root>/<Layer>/25.0.73/InstallArea/<plat>/`.
     - **No AtlasCMake patches for file ownership.** Every project-level file (`setup.sh`, `env_setup.sh`,
       `packages.txt`, `ReleaseData`, `cmake/PreConfig.cmake`, `cmake/modules/*`, `share/clid.db`, `lib/<Project>.*`)
       is per area.
     - ATLAS's own `setup.sh` chaining (`../../../../<base>/<ver>/InstallArea/<plat>`) and the export sanitizer's
       AthenaExternals rewriting keep working.
     - Cost: every search-path variable gets N entries, and each layer ships an activation script adding its own.
       This is the natural conda idiom.
   - **(B) One shared install area**, the CMSSW model.
     - Set `-DCMAKE_INSTALL_CMAKEDIR=cmake/<Layer>` (or `lib/cmake/<Layer>`, so that CMake's default config search
       finds it); it is a cache variable.
     - Rename `share/clid.db` per layer, which needs an AtlasCMake patch plus `CLIDDBFiles` / `clidGenerator.py` to
       read every file.
     - Drop per-project top-level files and duplicate `cmake/modules` when installing a layer. That calls for a
       "copy, refusing to overwrite, skipping identical files" installer like `cmssw-install-layer`.
     - Simpler runtime environment, more patches.
4. **Libraries and RPATH.**
   - AtlasCMake deliberately builds without RPATHs. For conda:
     - either keep that and set `LD_LIBRARY_PATH` in activation. This works on Linux but is disliked on conda-forge,
       and **does not work on macOS** because of SIP;
     - or patch `atlas_project` to make `CMAKE_SKIP_RPATH` optional (for example `ATLAS_SKIP_RPATH`), with
       `CMAKE_INSTALL_RPATH` listing the lower layers' `lib` directories relative to `$ORIGIN`/`@loader_path`, and
       `CMAKE_INSTALL_NAME_DIR=@rpath`.
   - The rattler-build recipe needs `dynamic_linking.rpath_allowlist` for the Athena tree, as CMSSW used
     `share/cmssw/**`.
5. **Plugins.** Set `GAUDI_PLUGIN_PATH` and `ROOT_LIBRARY_PATH` per layer, and patch the legacy `ConfigurableDb.py`
   to also scan `GAUDI_PLUGIN_PATH`.

### 7.2 Likely patches

1. `AtlasLCG/LCGConfig-version.cmake`: version 0 must be `EXACT`-compatible, or drop `EXACT` in the three callers.
2. `AtlasCMake/modules/AtlasCompilerSettings.cmake`: no GNU-ld flags when `APPLE` (`--as-needed`, `--no-undefined`,
   `--hash-style`, `-z max-page-size`). Also check `atlas_disable_as_needed` and `atlas_disable_no_undefined`.
3. `AtlasCMake/modules/AtlasFunctions.cmake`: make `CMAKE_SKIP_RPATH` configurable, at least for macOS.
4. `Control/AthenaCommon/python/ConfigurableDb.py`: search `GAUDI_PLUGIN_PATH` as well as `LD_LIBRARY_PATH`.
5. For option (B) only: `share/clid.db` naming in `atlas_merge_project_files`, plus `ClassIDSvc` defaults.
6. The layer-project `CMakeLists.txt` (new, ours). Do not reuse WorkDir's forced RelWithDebInfo.
7. `Findtdaq-common.cmake` / `Findtdaq.cmake`, if tdaq-common is packaged in conda layout (eformat/ers are needed by
   the ByteStream packages).
8. The macOS C++ portability fixes, a separate track.

### 7.3 Build-time execution

Every layer runs its freshly built libraries during the build: `genconf`, `listcomponents`, `genCLIDDB`,
`han-config-gen`, the L1Topo generators, and ROOT's `genreflex`. **Build on native runners for all three
platforms.** Cross-compiling osx-arm64 from osx-64 is not an option without deep changes.

---

## 8. Open questions

1. **[I]** Does a chain of three or more Athena layers configure and build? This needs a spike. Two things to check:
   - how `atlas_copy_target` behaves across several levels, with thousands of targets per layer (configure time);
   - `find_package(... EXACT)` on each level.
2. Install layout: one area per layer (A) or a shared area (B)? What does rattler-build do with `$PREFIX/<root>/...`
   paths and RPATH allowlists? Does `ROOT_LIBRARY_PATH` pick up the rootmaps of several lib directories? (Probably
   yes; it works for CMSSW with one.)
3. Does rattler-build's ELF/Mach-O relinking add RPATHs to binaries that have none (AtlasCMake builds with
   `CMAKE_SKIP_RPATH`), and does it rewrite bare-leaf install names on macOS? Or must AtlasCMake be patched first?
4. How does the full `Projects/Athena/CMakeLists.txt` behave with LCG 0 and conda externals? Which
   `find_package`s silently fail, which packages then break, and how many packages must be filtered out (tdaq,
   Oracle, Frontier, ...)? `Athena` `find_package`s without `REQUIRED` for most externals, so failures surface late.
5. Can conda-forge's `gaudi` be used, or must the ATLAS fork `v40r4.002` be packaged? Which ATLAS patches does the
   fork carry? (Externals report.)
6. Do the `-DSIMULATIONBASE` / `-DXAOD_ANALYSIS` / `-DGENERATIONBASE` subset projects (AthSimulation, AthAnalysis,
   AthGeneration) warrant separate conda products, given they cannot share layers with full Athena?
7. `ATLAS_BUILD_LEGACY_CONFIGURABLES`: how much of 25.0 still needs legacy `*Conf.py`? Turning it off would drop a
   build step per component.
8. Upstream acceptance: would ATLAS take the LCG-0 `EXACT` fix, the Apple linker-flag guard and an RPATH option into
   atlasexternals? Then we would not need to carry patches to AtlasCMake.
9. The installed `src/` (329 MB, including `.cxx`) is the header set for downstream builds. Should a layer split it
   into a `-devel` output, keeping headers plus `cmake/` only? Do any runtime paths use `src/`?
10. macOS: does `genconf` (which instantiates every component at build time) work with ld64 two-level namespaces
    and libc++? How many packages need libc++ fixes? (The clang22 Linux nightly proves clang, but only with
    libstdc++.)
