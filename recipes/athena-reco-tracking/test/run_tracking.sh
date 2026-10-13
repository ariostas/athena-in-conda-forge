#!/bin/bash
# Inner detector tracking as in ATLAS's own test of its configuration (InDetConfig.TrackRecoConfig)
# on ATLAS's Run 3 RDO test file (CVMFS, read in place: its licence is unclear): clusters, space
# points, track finding, fitting and ambiguity resolution, TRT extensions, track particles and
# primary vertices, on the first 10 events. The output (track particles, vertices, ...) is
# dumped with PyDumper, and the dump must be identical to the one ATLAS's release writes
# (tracking_dumps.sha256). The job reads the geometry database through ATLAS's public Frontier
# server, and conditions from CVMFS.
set -euo pipefail

# The error patterns of ATLAS's noerror.sh. On macOS, without the FPE auditor's warnings:
# conda-forge builds ROOT there with clang, which evaluates some guarded divisions anyway
# (TVector3::PseudoRapidity of a null vector computes 0/0, then discards it), so floating point
# exceptions are reported that ATLAS's release on Linux does not have.
errors_re="^ERROR | ERROR |^FATAL | FATAL | WARNING\s*FPE|runtime error:"
if [ "$(uname -s)" = Darwin ]; then
  errors_re="^ERROR | ERROR |^FATAL | FATAL |runtime error:"
fi

RDO=/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art/CampaignInputs/mc23/RDO/mc23_13p6TeV.801451.Py8EG_A3_NNPDF23LO_minbias_ND.recon.RDO.e8486_e8528_s4232_s4114_r15112/300events_RDO.39752217._004082.pool.root.1
if [ ! -f "${RDO}" ]; then
  echo "SKIPPED: ${RDO} is not available"
  exit 0
fi
here=$(cd "$(dirname "$0")" && pwd)
export FRONTIER_SERVER=${FRONTIER_SERVER:-"(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)"}
export ATLAS_POOLCOND_PATH=${ATLAS_POOLCOND_PATH:-/cvmfs/atlas-condb.cern.ch/repo/conditions}

# What ATLAS's tests check in a job's log (noerror.sh)
noerror() {
  if grep -Ea -e "${errors_re}" "$1"; then
    echo "FAILED: errors in $1"
    exit 1
  fi
}

run() {
  local log=$1
  shift
  if ! python "$@" > "${log}" 2>&1; then
    tail -50 "${log}"
    echo "FAILED: python $*"
    exit 1
  fi
  noerror "${log}"
}

mkdir -p tracking
cd tracking
run log_reco "${here}/track_reco.py" "${RDO}" tracking.pool.root 10
run log_dump "${here}/pool_rw.py" tracking.pool.root dump.txt
echo "tracking: $(wc -l < dump.txt) lines dumped"
# The references are per platform: ATLAS's release itself writes different floating point
# numbers on x86_64 and aarch64. ATLAS has no release for macOS to compare with.
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  platform=linux-64 ;;
  Linux-aarch64) platform=linux-aarch64 ;;
  *)             platform=$(uname -s)-$(uname -m) ;;
esac
if [ ! -f "${here}/tracking_dumps.${platform}.sha256" ]; then
  echo "no references for ${platform}: the dumps are not compared"
  exit 0
fi
sha256sum -c "${here}/tracking_dumps.${platform}.sha256"
