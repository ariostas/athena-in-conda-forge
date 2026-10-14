#!/bin/bash
# The offline reconstruction with ATLAS's reconstruction transform, Reco_tf.py, on ATLAS's Run 3
# RDO test file (CVMFS, read in place: its licence is unclear), as ATLAS runs it: inner detector,
# calorimeters and muon spectrometer, electrons, photons, muons, jets, taus, particle flow,
# b-tagging and missing transverse energy, to an ESD and an AOD, on the first 5 events. Both
# are dumped with PyDumper, and the dumps must be identical to the ones ATLAS's release writes
# (reco_dumps.sha256). The job reads the geometry database and conditions through ATLAS's
# public Frontier server, and conditions payloads from CVMFS.
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

mkdir -p reco
cd reco
# AthenaConfiguration.TestDefaults: defaultConditionsTags.RUN3_MC, defaultGeometryTags.RUN3
if ! Reco_tf.py --CA --inputRDOFile "${RDO}" --outputESDFile ESD.pool.root \
    --outputAODFile AOD.pool.root --maxEvents 5 \
    --conditionsTag OFLCOND-MC23-SDR-RUN3-11-02 --geometryVersion ATLAS-R3S-2021-03-02-00 \
    > log 2>&1; then
  tail -50 log
  tail -50 log.RAWtoALL || true
  echo "FAILED: Reco_tf.py"
  exit 1
fi
noerror log.RAWtoALL
for type in ESD AOD; do
  if ! python "${here}/pool_rw.py" "${type}.pool.root" "dump_${type}.txt" > "log_dump_${type}" 2>&1; then
    tail -50 "log_dump_${type}"
    echo "FAILED: dumping the ${type}"
    exit 1
  fi
  echo "${type}: $(wc -l < "dump_${type}.txt") lines dumped"
done
# Every collection must have about the size it has in ATLAS's release (reco_dump_sizes.txt), on
# every platform: this catches a job that runs but reconstructs much less where the dumps
# cannot be compared exactly (macOS).
if ! python "${here}/dump_counts.py" "${here}/reco_dump_sizes.txt" dump_ESD.txt dump_AOD.txt; then
  exit 1
fi
# The references are per platform: ATLAS's release itself writes different floating point
# numbers on x86_64 and aarch64. ATLAS has no release for macOS to compare with.
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  platform=linux-64 ;;
  Linux-aarch64) platform=linux-aarch64 ;;
  *)             platform=$(uname -s)-$(uname -m) ;;
esac
if [ ! -f "${here}/reco_dumps.${platform}.sha256" ]; then
  echo "no references for ${platform}: the dumps are compared only in size"
  exit 0
fi
# Each dump must have one of the sums listed for it: ATLAS's, and on linux-64 also this
# build's, whose last digits differ from ATLAS's in a few numbers (the file says which).
status=0
for name in $(grep -v '^#' "${here}/reco_dumps.${platform}.sha256" | awk '{print $2}' | sort -u); do
  sum=$(sha256sum "${name}" | cut -d' ' -f1)
  if grep -qx "${sum}  ${name}" "${here}/reco_dumps.${platform}.sha256"; then
    echo "${name}: OK"
  else
    echo "${name}: FAILED (${sum})"
    status=1
  fi
done
exit ${status}
