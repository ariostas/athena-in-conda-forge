# M1 spike: stacking Athena projects in a conda environment

Scripts that build a small part of Athena 25.0.73 as a stack of ATLAS projects against
conda-forge packages, outside rattler-build, in the `athena-dev` container (native
linux-aarch64, `/cvmfs` and this repo mounted, volume `athena-work` at `/work`).

- `env.sh`: a host prefix (`/work/spike-env`: ROOT 6.40.02 cxx23, Boost 1.90, TBB, python
  3.13, ...) and a separate build prefix (`/work/spike-build`: gcc 15, glibc 2.34 sysroot,
  cmake, ninja), set up the way rattler-build does it.
- `build-coral.sh`, `build-extras.sh` (boost-mpi3, yampl), `build-gaudi.sh` (ATLAS's fork
  v40r4.002): externals, into the host prefix. `patches/` has what they need.
- `build-externals.sh`: atlasexternals' `AthenaExternals` project with LCG 0 and no bundled
  externals, plus `find-modules/` and `conda-postconfig.cmake`.
- `layer/CMakeLists.txt` + `build-layer.sh`: one Athena layer as its own ATLAS project on top
  of the previous one. Everything is installed under
  `$PREFIX/opt/athena/<Project>/25.0.73/InstallArea/<platform>`.
- `run-spike.sh`: all of the above in order (`STEPS="layer3"` to run only some).
- `run-hello.sh`: runs `athena.py AthExHelloWorld/HelloWorldConfig.py`.
- `ninja-cost.py`: cost per kind of build step from `.ninja_log`.
- `pyclosure.py`: packages reachable through module-level python imports.

Results are in PLAN.md's progress log (2026-09-29, "the M1 spike").
