#!/bin/bash
# Run a command in ATLAS's own Athena 25.0.73 from CVMFS, as the reference for what a job does
# and needs. For the athena-ref container (AlmaLinux 9, /cvmfs mounted), in the current
# directory:
#   docker exec -w <dir> athena-ref bash /work/tmp/cvmfs-athena.sh <command> ...
# (a copy of this file in the athena-work volume).
export LCG_RELEASE_BASE=/cvmfs/sft.cern.ch/lcg/releases
source /cvmfs/sft.cern.ch/lcg/releases/gcc/15.2.0-35657/aarch64-el9/setup.sh
source /cvmfs/atlas.cern.ch/repo/sw/software/25.0/Athena/25.0.73/InstallArea/aarch64-el9-gcc15-opt/setup.sh >/dev/null 2>&1
export ATLAS_POOLCOND_PATH=/cvmfs/atlas-condb.cern.ch/repo/conditions
# ATLAS's public Frontier server, as asetup sets it, but without its proxy (403 from here)
export FRONTIER_SERVER="(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)"
"$@"
