# Athena in conda-forge

This repository is an effort to package [Athena](https://gitlab.cern.ch/atlas/athena), the
software framework of the ATLAS experiment at CERN, for [conda-forge](https://conda-forge.org).
The goal is to install it with `conda install`, `mamba install` or `pixi add` on **linux-64,
linux-aarch64 and osx-arm64**, without CVMFS or an ATLAS-specific environment.

It is a fork of [conda-forge/staged-recipes](https://github.com/conda-forge/staged-recipes), the
entry point for new conda-forge packages. The original staged-recipes README is in
[README-staged-recipes.md](README-staged-recipes.md). It follows the same approach as
[cmssw-in-conda-forge](https://github.com/ariostas/cmssw-in-conda-forge), which does this for
CMSSW.

> **Status: planning.** Nothing has been built or submitted to conda-forge yet.

The reference release is Athena [`release/25.0.73`](https://gitlab.cern.ch/atlas/athena/-/tree/release/25.0.73).
The analysis, the decisions and a progress log are in [PLAN.md](PLAN.md).
