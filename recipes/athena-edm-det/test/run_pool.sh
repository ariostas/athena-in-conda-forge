#!/bin/bash
# HITS, RDO and ESD I/O on ATLAS's Run 3 test files (from CVMFS, read in place: their licence is
# unclear). Athena reads the first 2 events of each, dumps every object in them (PyDumper) and
# writes a copy; Athena reads the copy back and dumps it. Every dump must be identical to the
# one ATLAS's own release writes: pool_dumps.sha256 has their sums. Copies are not always
# identical to their input, in ATLAS's release too: the persistent form of the silicon hits
# stores positions with less precision (HITS), and truth links are lost where the file has no
# truth event to resolve them against (ESD). The dumps decode identifiers and positions, so the
# jobs build the geometry: they read the geometry database (through ATLAS's public Frontier
# server) and conditions.
set -euo pipefail

DATA=/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art/CampaignInputs/mc23
if [ ! -d "${DATA}" ]; then
  echo "SKIPPED: ${DATA} is not available"
  exit 0
fi
here=$(cd "$(dirname "$0")" && pwd)
export FRONTIER_SERVER=${FRONTIER_SERVER:-"(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)"}
export ATLAS_POOLCOND_PATH=${ATLAS_POOLCOND_PATH:-/cvmfs/atlas-condb.cern.ch/repo/conditions}

# AthenaConfiguration.TestDefaults: HITS_RUN3, RDO_RUN3, ESD_RUN3_MC
declare -A input=(
  [HITS]=${DATA}/HITS/mc23_13p6TeV.601229.PhPy8EG_A14_ttbar_hdamp258p75_SingleLep.simul.HITS.e8514_s4162/100events.HITS.pool.root
  [RDO]=${DATA}/RDO/mc23_13p6TeV.801451.Py8EG_A3_NNPDF23LO_minbias_ND.recon.RDO.e8486_e8528_s4232_s4114_r15112/300events_RDO.39752217._004082.pool.root.1
  [ESD]=${DATA}/ESD/mc23_13p6TeV.601229.PhPy8EG_A14_ttbar_hdamp258p75_SingleLep.recon.ESD.e8514_e8528_s4257_s4114_r15221/100events_ESD.36313379._000013.pool.root.1
)

run() {
  local log=$1
  shift
  if ! python "${here}/pool_rw.py" "$@" > "${log}" 2>&1; then
    tail -50 "${log}"
    echo "FAILED: pool_rw.py $*"
    exit 1
  fi
}

for type in HITS RDO ESD; do
  mkdir -p "pool/${type}"
  cd "pool/${type}"
  run log_input "${input[${type}]}" dump_input.txt copy.pool.root 2
  run log_copy copy.pool.root dump_copy.txt
  echo "${type}: $(wc -l < dump_input.txt) lines dumped, copy read back"
  cd ../..
done
cd pool
# The references are per platform: ATLAS's release itself writes different floating point
# numbers on x86_64 and aarch64. ATLAS has no release for macOS to compare with.
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  platform=linux-64 ;;
  Linux-aarch64) platform=linux-aarch64 ;;
  *)             platform=$(uname -s)-$(uname -m) ;;
esac
if [ ! -f "${here}/pool_dumps.${platform}.sha256" ]; then
  echo "no references for ${platform}: the dumps are not compared"
  exit 0
fi
sha256sum -c "${here}/pool_dumps.${platform}.sha256"
