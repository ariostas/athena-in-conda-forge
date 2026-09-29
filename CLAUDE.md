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
- `_work/` (git-ignored): clones (atlasexternals, the ATLAS Gaudi and CLHEP forks), repodata
  caches and analysis outputs.

## Reference material

- Reference release: Athena 25.0.73 (`release/25.0.73`, commit `8c1c4b757d2`).
- CVMFS is mounted on this machine (`atlas.cern.ch`, `atlas-condb.cern.ch`,
  `atlas-nightlies.cern.ch`, `sft.cern.ch`, plus the CMS ones). The installed release, with full
  `src/`, is at `/cvmfs/atlas.cern.ch/repo/sw/software/25.0/Athena/25.0.73/InstallArea/{aarch64,x86_64}-el9-gcc15-opt`,
  and its externals at `.../25.0/AthenaExternals/25.0.73/`. Reads are slow; keep scans targeted.
- Externals versions: atlasexternals 2.1.91, LCG_110_ATLAS_5, ROOT 6.40.02 (C++23), gcc 15.2.

## Conventions

- Run `prek -a --quiet` before committing. Revert its changes to pre-existing upstream files
  (e.g. `.github/`).
- Conventional commits with an `Assisted-by: <harness>:<model>` trailer.
- Recipe maintainer is `ariostas`. Follow staged-recipes requirements: license files, sha256,
  no symlinks in noarch packages, tests.
- Never ship ATLAS's `authentication.xml` (it holds Oracle passwords) or anything from CVMFS
  whose licence is unclear.
