# Athena at runtime: data, site assumptions, platforms

Reference release: Athena 25.0.73 (`nightly/main/2026-09-23T2100`, GCC 15.2.0, CMake 4.4.0,
LCG_110_ATLAS_5, `cuda:NVIDIA-13.3.73` in `ReleaseData`). Written 2026-09-29.

Abbreviations used for paths:

- `$IA` = `/cvmfs/atlas.cern.ch/repo/sw/software/25.0/Athena/25.0.73/InstallArea/x86_64-el9-gcc15-opt`
- `$EXT` = `/cvmfs/atlas.cern.ch/repo/sw/software/25.0/AthenaExternals/25.0.73/InstallArea/x86_64-el9-gcc15-opt`
- `$DB` = `/cvmfs/atlas.cern.ch/repo/sw/database`
- `$TDAQC` = `/cvmfs/atlas.cern.ch/repo/sw/tdaq/tdaq-common/tdaq-common-14-00-00`

Tags: **[V]** means verified on CVMFS, by a network probe or by reading the code; **[I]** means
inferred from reading code without running it; **[G]** means a guess.

Sizes come from CVMFS `user.catalog_counters` xattrs (on nested-catalog roots) or from `find`/`ls`.
They are sizes as stored, before any compression.

---

## 0. Summary

- **Conditions and geometry need only the network.** By default Athena reads COOL conditions and the
  geometry DB (`ATLASDD`) through Frontier. The ATLAS Frontier servers answer anonymous HTTP from
  this machine, and so does the public proxy ALRB uses by default [V]. CREST, the REST replacement
  that is the default only for Run 4, is also publicly readable [V].
- **POOL conditions payloads are the gap.** These are the ROOT files that COOL folders point to by
  GUID. They exist only on `/cvmfs/atlas-condb.cern.ch` (839 GB), and the catalogue in it hard-codes
  that path. We know of no HTTP mirror. The MC subset is small (~3.8 GB for all MC campaigns); data
  is ~800 GB.
- **GroupData (CALIBPATH) is fine over HTTP.** It totals 1.15 TB, far too much to ship. But
  PathResolver has a built-in curl download from `https://atlas-groupdata.web.cern.ch`, enabled by
  `PATHRESOLVER_ALLOWHTTPDOWNLOAD=1`. The mirror is current (a file added 2026-09-28 is there), and
  field maps, geometry `.db` files and `dev/` files are all on it [V]. PathResolver does not check
  the HTTP status, so a 404 is saved as if it were the file [V, code].
- **The release is not relocatable as built.** No RPATH or RUNPATH (`CMAKE_SKIP_RPATH ON`), so
  everything hangs on `LD_LIBRARY_PATH` [V]. On top of that, `SITEROOT` defaults to `/afs/cern.ch`,
  and CALIBPATH, DATAPATH, LHAPDF and TDAQ paths default to `/cvmfs` or `/eos` [V]. A conda build
  has to replace all of this with activation scripts and rpaths.
- **aarch64 is a first-class ATLAS platform.** Every 25.0 release since 25.0.37, and most since
  25.0.10. The package list is identical to x86_64. 25.0.73 lacks 4 libraries on aarch64, of which
  one is a one-off build failure [V].
- **clang is continuously built, but with libstdc++.** The clang22 nightly produces exactly the
  same 2961 libraries as gcc15 [V]. There are no macOS builds of any project on CVMFS, and ALRB
  ships only AtlasSetup for arm64 macOS [V]. Remnants of earlier macOS support survive in
  AtlasCMake (`if(APPLE)`), 37 source files (`__APPLE__`) and the xAOD type-name normaliser, which
  already maps libc++'s `std::__1`.
- **The CPU baseline is conservative.** Production x86_64 builds with `-march=x86-64 -mtune=generic
  -msse2 -O2`, and aarch64 with no `-march` [V, from GCC LTO option records]. Three functions use
  `target_clones` (avx/avx2), only on x86 ELF. A weekly `archflagtest` nightly builds with
  `-march=x86-64-v3` [V]. conda-forge's x86_64 baseline is compatible with this.
- **CUDA, HIP and SYCL can be switched off.** Each GPU package returns early when there is no
  `CMAKE_CUDA_COMPILER`, HIP or SYCL compiler [V]. CUDA touches 14 GPU libraries in the release [V].

---

## 1. Data and conditions

### 1.1 PathResolver, CALIBPATH, DATAPATH

Source: `$IA/src/Tools/PathResolver/Root/PathResolver.cxx`,
`$IA/src/Tools/PathResolver/PathResolverEnvironmentConfig.cmake`, `$IA/env_setup.sh`.

- `find_calib_file` / `find_calib_directory` search `CALIBPATH`; `find_file(x, "DATAPATH")` searches
  `DATAPATH`. The current directory is always searched first [V].
- The CALIBPATH the release builds [V], in order:
  1. `/sw/DbData/GroupData` (the P1 online area);
  2. `/cvmfs/atlas.cern.ch/repo/sw/database/GroupData`;
  3. `/eos/atlas/atlascerngroupdisk/asg-calib`;
  4. `http//cern.ch/atlas-groupdata`;
  5. `http//atlas.web.cern.ch/Atlas/GROUPS/DATABASE/GroupData`.

  URLs are written as `http//` because `:` separates path entries.
- HTTP download [V, code]:
  - It is active only when `PATHRESOLVER_ALLOWHTTPDOWNLOAD` is set, and only for files (not
    directories).
  - It uses libcurl with `CURLOPT_FOLLOWLOCATION` and a 60 s timeout.
  - The file is written to the first *writable* CALIBPATH entry that precedes the URL, or to `.`.
  - **No `CURLOPT_FAILONERROR` and no HTTP status check.** A 404 HTML page (4470 bytes from
    `atlas-groupdata.web.cern.ch`) is saved under the requested file name and reported as success.
- Endpoint probes (2026-09-29) [V]:

  | CALIBPATH entry | Result |
  |---|---|
  | `http://cern.ch/atlas-groupdata/<f>` | 200, via redirect to `https://atlas-groupdata.web.cern.ch/<f>` |
  | `http://atlas.web.cern.ch/Atlas/GROUPS/DATABASE/GroupData/<f>` | **404** (dead fallback) |

  Files checked on the working mirror, all present and current:
  - `InDetGNNHardScatterSelection/v2.4.1/network.onnx` (dated 2026-09-28 on CVMFS, 3.3 MB);
  - `MagneticFieldMaps/bfieldmap_7730_20400_14m.root` (126 MB);
  - `Geometry/ATLAS-R3S-2021-03-02-00-DEV07.db` (51 MB);
  - `dev/TrackingCP/PixelDistortions/PixelDistortionsData_v2_BB.txt`.
- GroupData size on CVMFS [V]: **1147 GB in 384k files**. The largest parts:

  | Directory | Size |
  |---|---|
  | `dev/` | 506 GB |
  | `FTK/` | 409 GB |
  | `FastCaloSim/` | 128 GB |
  | `PixelDigitization/` | 59 GB |
  | `ACTS/` | 13 GB |
  | `TopReconstruction/` | 6.9 GB |
  | `MuonEfficiencyCorrections/` | 3.1 GB |
  | `xAODBTaggingEfficiency/` | 2.6 GB |
  | `MuonMomentumCorrections/` | 2.4 GB |
  | `GoodRunsLists/` | 1.7 GB |
  | `MagneticFieldMaps/` | 1.5 GB |
  | `JetUncertainties/` | 1.4 GB |

  Everything else is under 1.2 GB each. The per-package sizes are in the scratch output of this
  study; regenerate with `xattr -p user.catalog_counters <dir>`.
- The magnetic field maps are found through **CALIBPATH**, not DATAPATH
  (`MagFieldServices/src/AtlasFieldMapCondAlg.cxx:364`) [V]. The file names come from the COOL folder
  `/GLOBAL/BField/Maps`, e.g. `MagneticFieldMaps/bfieldmap_7730_20400_14m.root`.
- DATAPATH in `env_setup.sh` [V]:
  - `${ATLAS_RELEASEDATA}/v20` and `v20/testfile`, where `ATLAS_RELEASEDATA=${SITEROOT}/atlas/offline/ReleaseData`
    and `SITEROOT` defaults to `/afs/cern.ch`;
  - `${ATLAS_TWISSFILES}/v003`;
  - the release and externals `share/` directories;
  - `/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art`.

  `asetup` sets `SITEROOT=/cvmfs/atlas.cern.ch/repo/sw/software/25.0` when `atlas/offline` exists
  there (`AtlasSetup/python/cmakeRelease/AtlRelease.py:412-427`).
- `ReleaseData/v20` plus TwissFiles come to 1.27 GB [V]:

  | Directory | Size |
  |---|---|
  | `MagneticFieldMaps` (old copies) | 0.92 GB |
  | TwissFiles | ~0.11 GB |
  | `FastCaloSim` | 0.10 GB |
  | `testfile` (five small RDO/HITS files) | 0.08 GB |
  | `LArG4EC` | 0.036 GB |
  | `LArG4Barrel` | 0.029 GB |

  Without the old field maps it is ~0.35 GB, small enough to package.
- Test defaults: `AthenaConfiguration/TestDefaults.py` reads `ATLAS_REFERENCE_DATA` (default
  `/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art`), so test inputs can be relocated [V].
  `WorkflowTestRunner/Inputs.py` hard-codes 30 `/cvmfs/atlas-nightlies` paths. Its reference
  directory is overridable through `ATLAS_WORKFLOW_REFERENCES_PATH`, but its inputs are not [V].

### 1.2 Conditions: IOVDbSvc, COOL/CORAL, Frontier, dblookup/authentication

- **The CORAL, COOL and CREST client libraries come from tdaq-common, not LCG or AthenaExternals.**
  - `$TDAQC/installed/external/x86_64-el9-gcc15-opt/lib` holds CORAL 3.3.x with every plugin:
    `liblcg_FrontierAccess`, `SQLiteAccess`, `OracleAccess`, `MySQLAccess`, `XMLLookupService`,
    `XMLAuthenticationService`, `CoralServer*`, `PyCoral`. It also holds COOL (`liblcg_CoolKernel`,
    `CoolApplication`, `RelationalCool`) and `libCrestApiLib.so.6.2.12` [V].
  - `libIOVDbSvc.so` has `NEEDED` entries for `liblcg_CoralBase`, `RelationalAccess`, `CoolKernel`,
    `CoolApplication` and `libCoraCool` [V].
  - LCG_110_ATLAS_5 has no CORAL or COOL, but it does have `frontier_client` 2.10.2 [V].
  - `External/CORAL` and `External/COOL` exist in AthenaExternals (CORAL_3_3_20 from
    gitlab.cern.ch/lcgcoral) but install nothing into `$EXT/lib` in this build [V].
- **dblookup.xml** (`$IA/XML/AtlasAuthentication/dblookup.xml`, 126 logical services, from
  `Database/ConnectionManagement/AtlasAuthentication/data`) [V]. A typical entry lists, in order:
  1. `sqlite_file:sqlite200/ALLP200.db` (or `geomDB/geomDB_sqlite` for `ATLASDD`);
  2. `oracle://ATLAS_COOLPROD/...`;
  3. `frontier://ATLF/()/ATLAS_COOL...`.
- **`CORAL_AUTH_PATH` and `CORAL_DBLOOKUP_PATH`** are set to `${Athena_DIR}/XML/AtlasAuthentication`,
  unless already set [V].
- **authentication.xml** [V]:
  - At build time it is copied from `${SITEROOT}/atlas/offline/external/AtlasAuth/v22/authentication.xml`
    (`AtlasAuthentication/CMakeLists.txt`). CMake only warns if it is missing.
  - It holds 62 Oracle `user`/`password` reader credentials.
  - It is world-readable on CVMFS, but a conda package should **not** redistribute it. It is useless
    off-site anyway: CERN Oracle is not reachable, and there is no Oracle client on conda-forge.
- **How `ATLF` becomes a server**:
  - The `()` in `frontier://ATLF/()/SCHEMA` means "take the servers from `FRONTIER_SERVER`".
  - `DBReplicaSvc` (`$IA/src/Database/ConnectionManagement/DBReplicaSvc/src/DBReplicaSvc.cxx`)
    enables Frontier replicas only if `FRONTIER_SERVER` is non-empty [V]. It picks replicas by
    matching the host domain against `dbreplica.config`, in which every domain, and `default`,
    maps to `ATLF` [V].
  - The host name comes from `ATLAS_CONDDB`, then `HOSTNAME`, then `hostname --fqdn` (which has an
    `__APPLE__` branch), written to `hostnamelookup.tmp` in the current directory [V].
  - `IOVDbSvcCfg` sets `CacheAlign=3` when `FRONTIER_SERVER` is set [V].
- **Who sets `FRONTIER_SERVER`**:
  - ALRB, on `setupATLAS`, sets
    `(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)(proxyurl=http://v4f.hl-lhc.net:6082)`
    if it is unset (`ATLASLocalRootBase/swConfig/asetup/asetupEpilog.sh:19`). It then adds site
    squids through `utilities/guessFrontier.sh`, which uses `auto-setup` on grid sites [V].
  - AtlasSetup's default list is `atlasfrontier-local`, `atlasfrontier-ai`,
    `lcgft-atlas.gridpp.rl.ac.uk:3128`, `ccfrontier.in2p3.fr:23128`, with CERN `ca-proxy*` proxies
    (`AtlasSetup/python/cmakeRelease/AtlConfig_defaults.py`) [V].
  - The Athena release's own `env_setup.sh` does **not** set it [V].
- **Public access (probes from this Mac, 2026-09-29)** [V]. Queries used the plain Frontier protocol
  (`X-frontier-id` header, zlib+base64 SQL), with no authentication:
  - `http://atlasfrontier-ai.cern.ch:8000/atlr` and `atlasfrontier1-ai` returned rows for
    `select 1 from dual`, a COOL table listing of `ATLAS_COOLOFL_INDET`,
    `ATLAS_COOLOFL_INDET.OFLP200_TAGS` and the geometry `ATLASDD.HVS_TAG2NODE` for
    `ATLAS-R3S-2021-03-02-00`.
  - The same query through the proxy `http://v4f.hl-lhc.net:6082` also worked; the response had
    `Via: v4f-...(Varnish), v4a-frontier-uc-01...`.
  - Caveat: we did not check whether this Mac's address is inside CERN.
- **CREST** [V]:
  - `IOVDb.UseCREST` is True only for `GeoModel.Run > Run3` (Run 4/ITk), and False for AthGeneration.
  - The server is `https://crest.cern.ch` (override with `CREST_SERVER`), API `api-v6.0`
    (`IOVDbSvc/IOVDbAutoCfgFlags.py`).
  - `https://crest.cern.ch/api-v6.0/globaltags` returned JSON anonymously, with 15 global tags,
    e.g. `COND-MC21-SDR-RUN4-05`.
- **SQLite conditions and geometry** [I]:
  - The release's dblookup lists *relative* `sqlite_file:` paths. CORAL's SQLiteAccess knows an
    env var `SQLITE_FILE_PATH` (seen in the plugin's strings), but nothing in Athena, AtlasSetup
    or DBRelease sets it.
  - DBRelease's own `setup.py` rewrites its `dblookup.xml` with absolute paths and prepends the
    DBRelease directory to `DATAPATH`, `CORAL_*_PATH` and `TNS_ADMIN`.
  - That only happens when a transform is given `--DBRelease`
    (`PyJobTransforms/trfUtils.py`, `trfExe.py:1217-1243`).
  - Hence, in a normal job, the SQLite replicas are not found and CORAL fails over to Frontier.
    Local SQLite is supported explicitly through `IOVDb.SqliteInput` / `IOVDb.SqliteFolders`.
  - This should be confirmed by running a job with `CORAL_MSGLEVEL=Verbose`.
- **DBRelease** (`$DB/DBRelease/current` → 31.7.1, dated 2017; 9.6 GB) [V]:

  | File | Size |
  |---|---|
  | `sqlite200/ALLP200.db` (COOL MC replica) | 7.26 GB |
  | `geomDB/geomDB_sqlite_31.7` | 78 MB |
  | `triggerDB/triggerDBMC.db` | 81 MB |
  | `poolcond/PoolCat_*.xml` | small |

  AtlasSetup sets `ATLAS_DB_AREA=$DB` and `DBRELEASE_OVERRIDE=current` [V]. This is legacy; not
  needed for a conda build [I].
- **GeoModel SQLite** [V]:
  - `GeoModel.SQLiteDB` defaults to False (`AthenaConfiguration/GeoModelConfigFlags.py:94`).
  - When True, the file is looked up as `Geometry/<tag>.db` on CALIBPATH, via
    `AtlasGeoModel/AtlasGeoDBInterface.py:247`.
  - GroupData/Geometry holds only 8 `ATLAS-R3S-2021-03-02-00-DEV*.db` files of ~51 MB each
    (0.41 GB).
  - With the default of False, the geometry comes from `ATLASDD` over CORAL, i.e. Frontier.
    `AtlasGeoDBInterface` shortens the retry timeouts when `FRONTIER_SERVER` is unset.
- **POOL conditions payloads** (`/cvmfs/atlas-condb.cern.ch/repo/conditions`: 839 GB, 12,314 files,
  a single catalogue) [V]:
  - `PoolSvcCfg(withCatalogs=True)` reads `apcfile:poolcond/PoolFileCatalog.xml` and
    `PoolCat_oflcond.xml`, plus `PoolCat_comcond.xml` for data.
  - `apcfile:` is resolved against `$ATLAS_POOLCOND_PATH` first, then DATAPATH
    (`Database/AthenaPOOL/PoolSvc/src/PoolSvc.cxx:780-872`).
  - `ATLAS_POOLCOND_PATH` is set by AtlasSetup (default `/cvmfs/atlas-condb.cern.ch/repo/conditions`),
    not by the release.
  - `poolcond/PoolFileCatalog.xml` (4.1 MB, 12,058 entries) has **absolute
    `/cvmfs/atlas-condb.cern.ch/...` PFNs** for every entry.
  - Sizes by campaign:

    | Directory | Content | Size |
    |---|---|---|
    | `condR2` | 169 `.gen` + 67 `.lar` datasets (Run 2/3 data) | 327 GB |
    | `cond10` | data | 162 GB |
    | `cond11` | data | 132 GB |
    | `comcond` | | 91 GB |
    | `cond09` | of which `cond09_mc` is 3.45 GB | 70 GB |
    | `cond12` | data | 43 GB |
    | `cond08` | of which `cond08_mc` is 0.06 GB | 13 GB |
    | `oflcond` | MC | 0.2 GB |
    | `cmccond` | MC | 0.1 GB |

  - **All MC POOL payloads together are ~3.8 GB.**
  - No HTTP mirror found (open question). ROOT can open `https://` or `root://` PFNs, so a rewritten
    catalogue pointing at an HTTP mirror would probably work [G].

### 1.3 What typical jobs need

"Network-only" means no CVMFS, only HTTP(S) to CERN.

| Job | Needs | Network-only possible? |
|---|---|---|
| AnalysisBase / AthAnalysis on DAOD_PHYSLITE | libraries; calibration and ML files from GroupData via CALIBPATH (`JetCalibTools`, `MuonEfficiencyCorrections`, `ElectronEfficiencyCorrection`, `xAODBTaggingEfficiency`, `GoodRunsLists`, PRW); no COOL, no geometry [I] | **Yes** [I]: `PATHRESOLVER_ALLOWHTTPDOWNLOAD=1` and a writable cache as the first CALIBPATH entry. A few Conf defaults use absolute `/cvmfs/.../GroupData/...` paths (§2.3), which need overriding. Inputs: open data PHYSLITE over HTTPS (§1.4) |
| Reco_tf / RAWtoALL on MC RDO (e.g. WorkflowTestRunner q-tests) | COOL via Frontier (**works**); geometry `ATLASDD` via Frontier (**works**); POOL payload files for MC folders (`cond09_mc`/`oflcond`, **CVMFS only**); field maps and ML models (GroupData, **HTTP OK**); tdaq-common runtime libraries; data-art inputs (**CVMFS only**, 65–450 MB each) | **Partly.** Blocked by POOL payloads (3.8 GB for MC; could be packaged or mirrored) and by test inputs [I] |
| Reco on real data (RAW) | as above, plus data POOL payloads (`condR2`, hundreds of GB, per-run subset); ByteStream needs tdaq-common `eformat`/`EventStorage` | Only with CVMFS or a POOL mirror [I] |
| Simulation (Sim_tf / G4AtlasAlg) | Geant4 datasets for ATLAS's patched **10.6.3** (`geant4.10.6.patch03.atlasmt15`, 1.86 GB, 40k files; `/cvmfs/atlas.cern.ch/repo/sw/software/25.0/Geant4/share/.../data`); geometry via Frontier; COOL plus MC POOL payloads; `LArG4ShowerLibData` (GroupData, 0.2 GB) for frozen showers; `ReleaseData/v20/LArG4Barrel`, `LArG4EC` via DATAPATH [I, from file names]; FastCaloSim parameters (GroupData `FastCaloSim` 128 GB, per-version subset) for AF3 | Full sim: yes except the POOL payloads, if the G4 data are packaged [I]. AF3: needs large GroupData downloads |
| Event generation | `/cvmfs/atlas.cern.ch/repo/sw/Generators/{MCJobOptions,madgraph/models,...}`, LHAPDF sets from `/cvmfs/sft.cern.ch/lcg/external/lhapdfsets/current`, LCG MC generators | Out of scope for a first conda build |

Where the POOL payload dependency comes in: `IOVDbSvcCfg` always merges `PoolSvcCfg(withCatalogs=True)`,
but a payload file is only opened when a folder stores POOL references [V code, I usage].

### 1.4 Test inputs and open data

- **ASG test files** (`$IA/env_setup.sh`, `ASG_TEST_FILE_*`), all under
  `/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art/ASG/...` [V]:
  - DAOD_PHYS: 300–830 MB each;
  - DAOD_PHYSLITE: 100–290 MB;
  - `*OpenDataRNTuples.DAOD_PHYSLITE.p6026_p6898` (RNTuple, derived from open data): 12 MB (data16)
    and 33 MB (mc20).
- **data-art** total: 1.3 TB, 19,786 files [V]. Files are content-addressed symlinks into `.art/`.
  WorkflowTestRunner's mc23 inputs:
  - `100events.HITS` is 65 MB;
  - `1000events.AOD` is 365 MB;
  - an EVNT is 454 MB.
- **ATLAS Open Data for Research (2024)** on opendata.cern.ch, CC0-1.0 [V]:
  - Records 80000 (data15, 10.3 TB), 80001 (data16, 38.9 TB), 80010–80018 (MC: EW, exotics,
    Higgs, QCD, SUSY, top) and umbrella record 80020 (71.7 TB, 70,611 files). All DAOD_PHYSLITE,
    p6026.
  - Files are served from `root://eospublic.cern.ch//eos/opendata/atlas/rucio/<scope>/<file>`.
  - The **HTTPS** equivalent `https://opendata.cern.ch/eos/opendata/atlas/rucio/<scope>/<file>`
    returns 200 with `accept-ranges: bytes` (checked on a 643 MB mc20 file) [V].
  - The smallest records (SUSY 80016: 11 files, 3.9 GB) are the best candidates for a test. The
    CVMFS OpenDataRNTuples test files (12–33 MB) would be ideal, but we know of no HTTP location.

---

## 2. Grid, online and site assumptions baked in

### 2.1 Environment the release expects

`$IA/setup.sh` sources `env_setup.sh`, 348 lines generated by `lcg_generate_env` [V]. It:

- sets `LCG_RELEASE_BASE=/cvmfs/sft.cern.ch/lcg/releases`, and every external is found through
  `LD_LIBRARY_PATH`, `PATH`, `ROOT_INCLUDE_PATH` and `PYTHONPATH` entries under `LCG_110_ATLAS_5`;
- sets `SITEROOT=/afs/cern.ch` if unset (asetup overrides it);
- sets `TDAQ_RELEASE_BASE=/cvmfs/atlas.cern.ch/repo/sw/tdaq`, `TDAQ_VERSION=14-00-00`,
  `TDAQ_PYTHON_HOME` and `PYTHONHOME` (forced to LCG Python 3.13.11);
- sets `G4PATH=/eos/atlas/atlascerngroupdisk/proj-geant4/releases` and
  `G4VERS=geant4.10.6.patch03.atlasmt15`, with `G4*DATA` derived from them when unset;
- sets `LHAPDF_DATA_PATH`/`LHAPATH` to `/cvmfs/sft.cern.ch/...` and
  `/cvmfs/atlas.cern.ch/repo/sw/Generators/lhapdfsets/current`;
- sets `CALIBPATH` and `DATAPATH` as in §1.1;
- sets `ASG_TEST_FILE_*` to `/cvmfs/atlas-nightlies` paths;
- sets `CLING_STANDARD_PCH=none`, `OPENBLAS_NUM_THREADS=1`,
  `GAUDI_PROPERTY_PARSING_ERROR_DEFAULT_POLICY=Exception`,
  `COOL_DISABLE_CORALCONNECTIONPOOLCLEANUP=YES`, `ORA_FPU_PRECISION=EXTENDED` and
  `UBSAN_OPTIONS=suppressions=${Athena_DIR}/share/ubsan.supp`.

**RPATH** [V]:

- `AtlasFunctions.cmake:82-88` sets `CMAKE_SKIP_RPATH`, `CMAKE_SKIP_BUILD_RPATH` and
  `CMAKE_SKIP_INSTALL_RPATH` to ON.
- `objdump -p libCxxUtils.so` shows no RPATH or RUNPATH. Its `NEEDED` list includes
  `ld-linux-x86-64.so.2` directly, because it uses `_r_debug`.
- Gaudi finds plugins through `.components` files on `LD_LIBRARY_PATH`, or on `GAUDI_PLUGIN_PATH`.
  Both strings are present in `$EXT/lib/libGaudiPluginService.so` [V].

**AtlasSetup / ALRB** (asetup is not needed to run the release) [V]:

- `ATLAS_DB_AREA`, `DBRELEASE_OVERRIDE`, `ATLAS_POOLCOND_PATH`, `FRONTIER_SERVER` and `SITEROOT`
  are set only by asetup or ALRB.
- `trfExe.py:1600` writes a wrapper that sources
  `/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase/user/atlasLocalSetup.sh`, but only when `--asetup`
  is passed.
- `trfExe.py:1045` reads `ALRB_USER_PLATFORM` in that same path.
- `InDetBeamSpotExample/JobRunner.py` references ALRB.

**`athena.py`** is a `#!/bin/sh` script that preloads libraries and then re-executes itself with
`which python` [V]:

- It preloads `libtcmalloc_minimal.so` when `TCMALLOCDIR` is set, which AthenaExternals points at
  `ATLAS_GPERFTOOLS_DIR`.
- It preloads libraries for `--imf`, `--preloadlib`, and the exception trace or abort hooks
  (`USEEXCABORT=1` by default).
- It uses `LD_PRELOAD`, which is ignored on macOS, and `.so` names.

**prmon** [V]:

- The job transforms spawn `prmon` for memory monitoring. Failure to start is caught, logged as a
  warning, and disables monitoring (`trfExe.py:747-758`).
- prmon is built in AthenaExternals, and reads `/proc`, so it is Linux-only.
- prmon was not found on conda-forge (`conda search -c conda-forge prmon`).

### 2.2 TDAQ

- `find_package(tdaq-common ...)` appears in 64 package CMakeLists [V]. Components used:
  - `eformat` (35 packages), `eformat_write` (9), `CTPfragment` (7), `ers` (6), `DataReader` (6),
    `EventStorage` (5), `hltinterface` (4);
  - `MuCalDecode`, `dqm_core`, `dqm_core_io`, `dqm_dummy`, `dqm_dummy_io`, `RawFileName`,
    `DataWriter`, `webdaq`, `webdaq-noroot`.
- Only `HLT/Event/ByteStreamEmonSvc` uses full `tdaq` (`emon`, `is`, `oh`, `ohroot`, `owl`,
  `omniORB4`, `omnithread`) [V]. That is online monitoring; drop it.
- tdaq-common 14-00-00 source is on CVMFS (`$TDAQC/{eformat,ers,EventStorage,...}`), and the
  per-package `LICENSE` files are **Apache-2.0** [V]. Binaries exist for:
  - `x86_64-el9-gcc15/16-{opt,dbg}`;
  - `x86_64-el10-gcc15-{opt,dbg}`;
  - `aarch64-el9-gcc15/16-opt`.

  There is no clang or macOS build.
- tdaq-common also carries CORAL, COOL and CrestApi (§1.2). Packaging Athena therefore means
  packaging tdaq-common (or its parts) plus CORAL and COOL.

### 2.3 Hard-coded site paths in `$IA/python`

Grep over `*.py`: 515 hits in 248 files across 125 packages [V]. By prefix:

| Prefix | Hits | What |
|---|---|---|
| `/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art` | 130 | test inputs (WorkflowTestRunner 33, MuonGeoModelTestR4 13, eflowRec 9, TileMonitoring 7, TriggerJobOpts 5, ...). Mostly `if __name__=='__main__'` tests or defaults; `TestDefaults` is overridable |
| `/afs/cern.ch/user/...`, `/afs/cern.ch/work/...`, `/afs/cern.ch/atlas/...` | ~140 | DQ, calibration and T0 operational scripts (atlasdqm, muoncali, atlcond, sctcalib, tzero). Not used in physics jobs |
| `/eos/atlas/...` | ~90 | T0 and calibration operations, `data-art/grid-input` references, perf group storage. Not used in physics jobs |
| `/cvmfs/atlas.cern.ch/repo/sw/database/GroupData/...` | 22 | **absolute GroupData paths that bypass the CALIBPATH lookup** (below) |
| `/cvmfs/atlas.cern.ch/repo/sw/Generators/...` | 7 | generation: MCJobOptions, madgraph models, Blocks.list |
| `/cvmfs/atlas.cern.ch/repo/sw/database/DBRelease` | 1 | `trfUtils.cvmfsDBReleaseCheck` |
| `/cvmfs/sft.cern.ch/lcg/views/LCG_109a/...` | 1 | `Pepper_i/PepperConfig.py` |
| `/cvmfs/atlas.cern.ch/repo/sw/software/21.1/AthenaP1/...` | 2 | `TriggerMenuMT/TriggerAPI/TriggerDataAccess.py` (legacy menus) |

The absolute GroupData paths are:

- **in generated `*Conf.py`, i.e. C++ property defaults**:
  - `L1CaloFEXAlgos` (`jfex_SCID.txt`, `jfex_TileID.txt`, `jFexTowerMap.txt`, gFEX tower map);
  - `PixelConditionsAlgorithms` (`dev/TrackingCP/PixelDistortions/PixelDistortionsData_v2_BB.txt`);
  - `TileTripReader`;
  - `TrigT1NSWSimTools` (sTGC pad-trigger VHDL patterns);
- **in python configs**: `ActsConfigFlags`, `BoostedJetTaggerConfig`, `HIGG9D1`, `LeptonTaggersConfig`,
  `InDetPhysValMonitoring`, `TrigTauConfigFlags`, `TriggerPeriodData`, `ZdcInjPulserVoltageReader`,
  `HICaloGeoExtract`.

These need patching to logical names, or a symlink or bind at `/cvmfs/atlas.cern.ch/repo/sw/database/GroupData`.
PathResolver logs an ERROR for absolute names outside `XAOD_ANALYSIS` builds but still accepts them
(`PathResolver.cxx`, `find_file`) [V].

---

## 3. Platforms

### 3.1 linux-aarch64

- 25.0 install areas on `/cvmfs/atlas.cern.ch/repo/sw/software` [V]:
  - `aarch64-centos7-gcc11-opt` appears as early as **23.0.0**, intermittently through 23.0 and 24.0.
  - `aarch64-el9-gcc13-opt` appears from 24.0.42.
  - In 25.0 it appears in 25.0.10 and 25.0.13, then **in every release from 25.0.37 onward**
    (gcc14, then gcc15 from 25.0.66).
- Nightlies exist for `main_{Athena,AthSimulation,AthGeneration,AthAnalysis,AnalysisBase,DetCommon}_aarch64-el9-gcc15-opt`,
  plus `main--dev4LCG_Athena_aarch64` [V].
- AnalysisBase 25.2 has 98 aarch64 releases (gcc13/14/15) [V].
- 25.0.73 `packages.txt`: **identical**, 1,967 lines on both architectures [V].
- `lib/`: x86_64 has 2,970 entries, aarch64 has 2,966. The ones missing on aarch64 [V]:
  - `libEpos4_i.so`, `libEpos4_iLib.so`: `Generators/Epos4_i` returns early when EPOS4 is not
    found (no EPOS4 on aarch64 in LCG);
  - `libpowhegHerwigBB4L.so`: built only if `${COMPILEBOX_LCGROOT}/POWHEG-BOX-RES/b_bbar_4l_modified/...`
    exists;
  - `libInDetGNNTracking.so`: same CMakeLists on both, and **present on aarch64 in 25.0.70 and
    25.0.72**, so a one-off nightly build failure in 25.0.73.
- Linker settings differ only in `-z max-page-size`: 0x1000 on x86_64, 0x10000 on aarch64
  (`AtlasCompilerSettings.cmake:209-218`) [V].
- Other platform nightlies [V]: `x86_64-el10-gcc15-opt` (Athena main, 34 nightlies kept),
  `-dbg`, `simGPU`, `dev3LCG`/`dev4LCG` (including gcc16).

### 3.2 clang, libc++ and macOS

**ATLAS clang builds** [V]:

- Nightlies: `main_Athena_x86_64-el9-clang19-opt` (31 nightlies kept) and `...-clang22-opt` (29).
  `clang16`/`clang17` directories exist but are empty.
- The 2026-09-28 clang22 nightly (25.0.74, Clang 22.1.8) has the same `packages.txt` and **the same
  2,961 libraries** as the gcc15 nightly, once `.dbg` files are excluded.
- It links **libstdc++** (`libCxxUtils.so` `NEEDED libstdc++.so.6`; clang is set up against the
  gcc15 toolchain).
- The 25.0.45 production release also shipped `x86_64-el9-clang19-opt` (1,979 packages, 3,042
  libraries, also libstdc++).
- So Clang the compiler is fully supported; libc++ is not tested by ATLAS.

**macOS**:

- No macOS install areas for any project or branch on CVMFS: we checked AnalysisBase 21.2, 22.2,
  24.2 and 25.2 [V].
- ALRB has `arm64-MacOS/{AtlasSetup,crane}` and a legacy `x86_64-MacOS/{root,xrootd,...}` [V].
- Historically AnalysisBase 21.2 was built on macOS in CI [G, from memory, not verified here].

**What macOS support survives** [V]:

- AtlasCMake:
  - `if(APPLE)` branches in `AtlasDictionaryFunctions`, `AtlasInternals`, `AtlasTestFunctions`,
    `AtlasFunctions` and `LCGFunctions` (e.g. `DYLD_LIBRARY_PATH` in generated setup scripts);
  - on Apple, `AtlasFunctions.cmake:560` **copies bash into the build directory to get around
    SIP**.
- The ELF-only linker flags (`--as-needed`, `--no-undefined`, `-z max-page-size`,
  `--hash-style=both`) are added only for `CMAKE_CXX_COMPILER_ID` equal to `GNU` or `Clang`. That
  excludes AppleClang, **but conda-forge's clang identifies as `Clang`**, so they would be applied
  and break ld64 (`AtlasCompilerSettings.cmake:194-219`). This needs a patch.
- Source:
  - 37 files mention `__APPLE__` (list below);
  - `CxxUtils/SealCommon.h` has an `__APPLE__` platform-config block;
  - `CxxUtils/features.h` enables function multiversioning only for x86 ELF, and
    `HAVE_FEENABLEEXCEPT` only for glibc;
  - `AthContainers/Root/normalizedTypeinfoName.cxx` maps `std::__1` → `std`, with the comment
    "Needed for macos?".

  The 37 `__APPLE__` files are in: CxxUtils (stacktrace, statm, clock, excepts, sincosf,
  BasicTypes, xxhash, SealSignal), AthenaServices (CoreDumpSvc, FPEControlSvc), AthenaKernel
  (BaseInfo, AthDsoUtils), AthContainers, DataModelAthenaPool ElementLink_p1/p2/p3, AthenaAuditors
  FPEAudit, DBReplicaSvc, GenericDbTable, LArWFParamTool, GeoSpecialShapes LArWheelCalculator,
  JiveXML (ONCRPC), VP1 and others.

**GCC-isms and Linux-isms**, from one grep pass over all of `src/` (C/C++/CMake) [V]:

| Item | Files | Where / note |
|---|---|---|
| `/proc/self`, `/proc/meminfo`, `/proc/cpuinfo` | 14 | CxxUtils (`procmaps`, `PageAccessControl`, `read_athena_statm`, `SealSharedLib`, `AthDsoCbk.c`), AthenaMP, AthenaMonitoring bench, CoWTools, PerfMonMT, a TRT calibration script |
| `<malloc.h>` / `mallinfo`, `mallinfo2` | 6 / 1 | PerfMonMTUtils (also weak `tc_mallinfo2`), CxxUtils xmalloc and UnwindBacktrace, TestTools `leakcheck.h`, RecEventTPCnv |
| `<link.h>`, `_r_debug`, `link_map`, `<elf.h>` | 3 | CxxUtils `SealSharedLib` / `SealCommon.h`, AthenaAuditors `FPEAudit_linux.icc` |
| `dlvsym` plus `_GNU_SOURCE` dlopen interposition | 1 | `CxxUtils/src/AthDsoCbk.c` (DSO load callbacks) |
| `__cxa_throw` interposition | 2 | `CxxUtils/src/exctrace/*`, `Root/exctrace.cxx` (loaded with LD_PRELOAD) |
| `prctl`, `<sys/sysinfo.h>` | 1, 2 | AthenaInterprocess `Process.cxx`; CoreDumpSvc |
| `backtrace_symbols`, `<execinfo.h>` | 5 | available on macOS too |
| `<ext/functional>`, `<ext/alloc_traits.h>` | 4 | **libstdc++-only headers**: InDetTruthTools `PRD_MultiTruthBuilder`, MuonAmbiTrackSelectionTool, MuonReadoutGeometry `MuonPadDesign`, `sTgcReadoutElement` |
| `<bits/...>`, `_GLIBCXX_*`, `__gnu_cxx::` | **0** | |
| `__GLIBCXX__`, `_LIBCPP_VERSION` checks | 0 | |
| `atlas_disable_as_needed()` | 20 packages | generators, ByteStreamStoragePlugins, ... |
| `sched_getaffinity`, `pthread_setname_np`, `dl_iterate_phdr`, `RTLD_DEEPBIND`, `malloc_trim`, `__malloc_hook` | 0 | checked in Control, Database, Event and Tools |

**CheckerGccPlugins**: an AthenaExternals package, used only when the compiler is GNU and
`libchecker_gccplugins` is found (`ATLAS_USE_GCC_CHECKERS`, default ON). Production objects carry
`-fplugin=.../libchecker_gccplugins.so` [V]. It can be skipped for conda: the
`ATLAS_CHECK_THREAD_SAFETY` markers are inert without the plugin, as the clang nightly shows.

**Estimated libc++/macOS port effort** [I/G]:

- Compared with CMSSW (about a dozen small patches per layer, see the cmssw-in-conda-forge PLAN
  §1.4 and CLAUDE.md), Athena looks **no worse at the source level**:
  - clang already compiles all of it;
  - explicit libstdc++-internal usage is 4 files;
  - Linux-only runtime code is concentrated in about 25 files in Control/, mostly monitoring,
    debugging and MP code that can be `#ifdef`'d.
- Expect the CMSSW class of libc++ strictness issues: missing transitive includes, `uint64_t` being
  `unsigned long long` (which affects ROOT dictionaries and persistent checksums), `constexpr` math,
  `from_chars`. The count is unknown until we build.
- The harder parts are elsewhere:
  - **AtlasCMake**: ELF linker flags under `Clang`, `CMAKE_SKIP_RPATH` (on macOS SIP strips
    `DYLD_*` from `/bin/sh` scripts such as `athena.py`, so rpaths plus `GAUDI_PLUGIN_PATH` are
    required), `.so` vs `.dylib` naming in dictionary and rootmap generation, and bash-4 or GNU-tool
    assumptions in scripts;
  - **externals**: tdaq-common, CORAL and COOL have no macOS builds; ATLAS's Geant4 10.6.3 fork,
    Gaudi and Acts would need macOS builds; and CUDA or VecGeom-CUDA must be off;
  - **runtime**: `athena.py`'s `LD_PRELOAD` scheme, prmon, AthenaMP fork and CoW tooling reading
    `/proc`, and the DSO callbacks that interpose `dlopen` via `_GNU_SOURCE`.
- Rough guess: a few weeks to get Control/Event/xAOD/AnalysisBase-level code running on
  osx-arm64. Full Athena reco is significantly more, dominated by externals rather than Athena
  source.

### 3.3 CPU micro-architecture

Production compile options, read from the `.gnu.lto_.opts` / `.gnu.debuglto_.debug_str` sections of
the G4 LTO objects shipped in `objects-*` [V]:

| Build | Options |
|---|---|
| x86_64 (RelWithDebInfo) | `-msse2 -mtune=generic -march=x86-64 -g -O2 -std=c++23 -fplugin=...libchecker_gccplugins.so ... -flto -fno-fat-lto-objects -fPIC -faligned-new=1` |
| aarch64 (Release) | `-mlittle-endian -mabi=lp64 -O2`, no `-march` (generic armv8-a) |
| `main--archflagtest_Athena_x86_64-el9-gcc15-opt` (weekly, 5 nightlies kept) | `-march=x86-64-v3 -msse2 -O2 -ftree-vectorize -fvect-cost-model=very-che...` (truncated in the probe) |
| `main--ltoflagtest` | exists (weekly); flags not inspected |

- There is no `-march` in `AtlasCompilerSettings.cmake`; the release-mode default is `-DNDEBUG -O2`
  (not `-O3`) [V].
- Explicit ISA code [V]:
  - `[[gnu::target_clones(...)]]` in `CaloLumiConditions/src/CaloBCIDCoeffs.cxx`
    (`default,sse2,avx,avx2`) and `MagFieldElements/src/BFieldCache.cxx` (`avx2,default`), guarded
    by `HAVE_TARGET_CLONES` (x86 + ELF only);
  - `CxxUtils/Root/xxhash.h` (bundled xxHash with SSE2/AVX2/NEON dispatch);
  - `CxxUtils/stall.h` (`xmmintrin.h`, pause);
  - `CxxUtils/fpcompare.h` (`__SSE2__`).

  The `x86-64-v3` hits in MuonReadoutGeometry are only comments about a GCC 14 warning.
- **Implication**: conda-forge's x86_64 default (`-march=nocona -mtune=haswell`) is at or above the
  ATLAS baseline. Nothing requires v2 or v3. aarch64 is generic.

### 3.4 CUDA, HIP, SYCL and other accelerators

- Packages that gate on `CMAKE_CUDA_COMPILER` and return early without it [V]:
  - `Control/AthCUDA/{AthCUDACore,AthCUDAInterfaces,AthCUDAKernel,AthCUDAServices}`;
  - `Control/AthenaExamples/AthExCUDA`;
  - `Calorimeter/CaloRecGPU`;
  - `Simulation/ISF/ISF_FastCaloSim/ISF_FastCaloGpu`, plus ISF_FastCaloSimEvent/Services options;
  - `Tracking/Acts/ActsGPU{DataPreparation,EventCnv,Geometry,MagField,PatternRecognition}`
    (traccc/detray/vecmem);
  - `Trigger/TrigAccel/{TrigInDetCUDA,TrigInDetAccel/TrigInDetAccelerationService}`.
- The same applies to HIP (`Control/AthHIP/*`, `AthExHIP`, `HIEventUtils`, `ActsGPUMagField`) and
  SYCL (`AthExSYCL`, `Trigger/EFTracking/EFTrackingDataTransfer`).
- GPU libraries in 25.0.73 [V]:
  `libActsGPU{DataPreparation,EventCnv,EventLib,Geometry,MagField,PatternRecognition}`,
  `libAthCUDA{CoreLib,InterfacesLib,Services}`, `libAthExCUDA`, `libCaloRecGPU{,Lib}`,
  `libISF_FastCaloGpuLib`, `libTrigInDetCUDA`.
- The CUDA architectures default to `75;80;86;89;90;100`, and HIP to `gfx1031;gfx1100;gfx1200`
  (`AtlasCompilerSettings.cmake:48-59`) [V].
- Several `*_G4_SD` CMakeLists (BCM, BLM, Pixel, SCT, TRT, LArG4Code, MuonG4SD) contain
  "Turn on/off CUDA device symbol resolution for tests (Geant4 links to VecGeom, which is
  CUDA-enabled)". So ATLAS's VecGeom is CUDA-enabled; a CPU-only VecGeom removes this [V text, I].
- **Conclusion**: build without nvcc or hipcc and the GPU packages disappear. A CUDA variant would
  be a later, optional output.
- Other inference and accelerator dependencies [V]:
  - `onnxruntime`: 30 packages; needed, and on conda-forge [G];
  - Triton client: `AthTriton`, `AthExTriton`, `InDetGNNTracking`, `FlavorTagInference`,
    `TracccTritonClient` (optional? unverified);
  - `lwtnn`: AthenaExternals;
  - there is no Kokkos or alpaka in Athena packages; `pepper_kokkos` is only an LCG generator.

---

## 4. Implications for conda-forge packaging

1. **Activation scripts must replace `setup.sh`/`env_setup.sh`.** Generate them from the conda
   prefix, and set at least:
   - `CALIBPATH`: a writable user cache first (e.g. `${XDG_CACHE_HOME:-~/.cache}/atlas/GroupData`),
     then `/cvmfs/atlas.cern.ch/repo/sw/database/GroupData` if it exists, then
     `http//cern.ch/atlas-groupdata`;
   - `PATHRESOLVER_ALLOWHTTPDOWNLOAD=1`, opt-out;
   - `DATAPATH`: the prefix `share/`, a packaged ReleaseData subset and TwissFiles, and optionally
     `data-art` on CVMFS;
   - `CORAL_DBLOOKUP_PATH`, and `CORAL_AUTH_PATH` pointing to an **empty or no-password**
     `authentication.xml` (do not ship ATLAS's Oracle credentials);
   - `FRONTIER_SERVER`, if unset, to the ALRB default
     `(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)(serverurl=http://atlasfrontier1-ai.cern.ch:8000/atlr)(proxyurl=http://v4f.hl-lhc.net:6082)`
     (ask ATLAS DB/ADC before publishing this);
   - `ATLAS_POOLCOND_PATH` if CVMFS is present;
   - `G4*DATA` to the packaged or conda Geant4 datasets;
   - `GAUDI_PLUGIN_PATH`;
   - `SITEROOT` (anything that makes `ATLAS_RELEASEDATA` point into the prefix);
   - `ATLAS_REFERENCE_DATA` if a test-data location exists.

   Leave `TDAQ_*` and `LCG_*` alone or unset; `PYTHONHOME` must not be forced.
2. **Patch PathResolver** to set `CURLOPT_FAILONERROR` (or check `CURLINFO_RESPONSE_CODE`), to
   delete partial files, and to drop the dead `atlas.web.cern.ch` fallback. This is upstreamable.
   Otherwise one 404 poisons the cache permanently.
3. **Add RPATHs.** Stop `CMAKE_SKIP_RPATH` (or set `CMAKE_INSTALL_RPATH=$ORIGIN/../lib;$PREFIX/lib`,
   `@loader_path` on macOS) so the release works without `LD_LIBRARY_PATH`. This is mandatory for
   macOS (SIP) and for plain conda envs.
4. **Package the conditions clients**: tdaq-common (eformat, ers, EventStorage, CTPfragment,
   hltinterface, dqm_core, MuCalDecode, compression, webdaq; Apache-2.0), plus CORAL, COOL,
   CrestApi and frontier_client.
   - The CMSSW repo already has `recipes/coral` and `recipes/frontier-client`. CORAL's licence
     problem (no licence file) applies again, and COOL is likely the same [G].
   - Athena uses upstream LCG CORAL 3.3.20; CMS uses a fork. They must not clash as package names.
5. **Data packages**:
   - small noarch packages: a ReleaseData v20 subset (~0.35 GB without the old field maps), and
     TwissFiles v003;
   - possibly "MC POOL conditions" (~3.8 GB, too big for one conda-forge package, and the catalogue
     paths must be rewritten);
   - GroupData, data POOL payloads and data-art should **not** be packaged. Use HTTP (GroupData) or
     optional CVMFS.
   - Geant4 datasets must match **Geant4 10.6.3** (ATLAS fork `atlasmt15`) unless Athena moves to
     11.x.
6. **Frontier and CREST make network-only conditions workable for MC workflows**, except for POOL
   payloads. Resolving the payload question is the single biggest item for "reco from RDO without
   CVMFS".
7. **Hard-coded `/cvmfs/.../GroupData/...` defaults** in about 13 C++ and python sites need patches
   to logical CALIBPATH names (upstreamable), or users need CVMFS for those tools.
8. **linux-aarch64 costs nothing extra at the source level.** ATLAS builds the full package set.
   Skip EPOS4 and POWHEG-BB4L-Herwig where LCG lacks them, as ATLAS does.
9. **osx-arm64 is a separate porting track**, as in CMSSW. Patch AtlasCompilerSettings (no ELF
   linker flags when `APPLE`, even for `Clang`), rpaths, `.so` naming, `athena.py`'s preload
   logic, and Linux-only monitoring code. The source-level libc++ fixes look few, but that is
   untested, and the externals (tdaq-common, CORAL/COOL, the Geant4 10.6 fork) are the long pole.
10. **CPU flags**: use conda-forge defaults. Do not add `-march`. Keep `-O2`. The `target_clones`
    paths are x86-ELF-only and fine with conda's GCC.
11. **CUDA**: build without it (no nvcc means the GPU packages are skipped). Use a CPU-only VecGeom.
12. **CheckerGccPlugins**: skip (`-DATLAS_USE_GCC_CHECKERS=OFF`, or just do not build it). prmon is
    optional: the transforms tolerate its absence. It could be packaged for Linux later.

---

## 5. Open questions

1. **Is there an HTTP(S) mirror of `/cvmfs/atlas-condb.cern.ch` (POOL conditions payloads)?** If
   not, would ATLAS DB people accept one, or accept a conda package with the ~3.8 GB of MC
   payloads? Which folders does a typical MC23 RDO→AOD job actually open? This could be measured
   by running a q-test with `PoolSvc` at DEBUG level.
2. Is anonymous use of `atlasfrontier*-ai.cern.ch:8000/atlr` and `v4f.hl-lhc.net:6082` from
   arbitrary users acceptable to ATLAS (load, policy)? CMS's cmsfrontier is used this way. We
   should also check whether this Mac's network is inside CERN, which would invalidate the "public"
   conclusion; test from a non-CERN network.
3. Confirm [I] that relative `sqlite_file:` replicas are skipped and Frontier is used, by running a
   job with `CORAL_MSGLEVEL=Verbose`. Does CORAL honour `SQLITE_FILE_PATH` as a search path
   (this would allow shipping a geomDB SQLite for offline use)?
4. Is `/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art` (or at least `ASG/` and the
   `OpenDataRNTuples` test files) available over HTTP? (`/eos/atlas/atlascerngroupdisk/data-art`
   needs CERN authentication.) If not, CI tests must use open data over HTTPS.
5. Licences of COOL, CORAL (same issue as in CMSSW) and CrestApi. tdaq-common is Apache-2.0.
6. Can Athena run with conda-forge's Geant4 11.x, or is the ATLAS 10.6.3 fork (plus its data
   versions) a hard requirement for AtlasG4 in 25.0? This affects the simulation layer and the
   dataset packages.
7. Why is `libInDetGNNTracking.so` missing on aarch64 in 25.0.73 only? Check the nightly build log;
   probably transient.
8. Did AnalysisBase ever ship macOS builds (21.2 era), and are ATLAS core people willing to take
   macOS/libc++ patches upstream?
9. Triton client: is it optional in every consuming package (it is `find_package`d in five)? Is a
   Triton client on conda-forge?
10. (Partly answered.) The 25.0.73 `ReleaseData` mentions CUDA 13.3 because the GPU packages were
    compiled; e.g. `libCaloRecGPU.so` has `NEEDED libcudart.so.13` [V]. VecGeom is **static**
    (`$EXT/lib/libvecgeom.a`), and neither `libG4AtlasAlg.so` nor `libPixelG4_SD.so` has a
    CUDA or VecGeom `NEEDED` entry [V]. So the CPU simulation path has no runtime CUDA
    dependency. Still open: whether static VecGeom-CUDA drags device-link requirements into G4
    builds from source.
