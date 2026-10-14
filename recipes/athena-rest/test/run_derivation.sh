#!/bin/bash
# ATLAS's derivations with its derivation transform, Derivation_tf.py, as ATLAS's
# DerivationFrameworkART tests run them: DAOD_PHYS and DAOD_PHYSLITE, the formats most analyses
# use, from the first 10 events of ATLAS's Run 3 ttbar AOD test file
# (AthenaConfiguration.TestDefaults' AOD_RUN3_MC, on CVMFS, read in place: its licence is
# unclear). Both outputs are dumped with PyDumper, and the dumps must be identical to the ones
# from ATLAS's release (derivation_dumps.sha256). The job reads conditions through ATLAS's public
# Frontier server.
set -euo pipefail

AOD=/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art/CampaignInputs/mc23/AOD/mc23_13p6TeV.601229.PhPy8EG_A14_ttbar_hdamp258p75_SingleLep.recon.AOD.e8514_s4162_r14622/1000events.AOD.33799166._000073.pool.root.1
if [ ! -f "${AOD}" ]; then
  echo "SKIPPED: ${AOD} is not available"
  exit 0
fi
here=$(cd "$(dirname "$0")" && pwd)
export FRONTIER_SERVER=${FRONTIER_SERVER:-"(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)"}
export ATLAS_POOLCOND_PATH=${ATLAS_POOLCOND_PATH:-/cvmfs/atlas-condb.cern.ch/repo/conditions}

# What ATLAS's tests check in a job's log (noerror.sh), but floating point exceptions: ATLAS's
# release has some in this job too (TrackLeptonDecoratorAlg, FPE INVALID), and its derivation
# tests do not check for them.
noerror() {
  if grep -Ea -e "^ERROR | ERROR |^FATAL | FATAL |runtime error:" "$1"; then
    echo "FAILED: errors in $1"
    exit 1
  fi
}

mkdir -p derivation
cd derivation
if ! Derivation_tf.py --inputAODFile "${AOD}" --outputDAODFile art.pool.root \
    --formats PHYS PHYSLITE --maxEvents 10 > log 2>&1; then
  tail -50 log
  tail -50 log.Derivation || true
  echo "FAILED: Derivation_tf.py"
  exit 1
fi
noerror log.Derivation
for format in PHYS PHYSLITE; do
  if ! python "${here}/pool_rw.py" "DAOD_${format}.art.pool.root" "dump_${format}.txt" \
      > "log_dump_${format}" 2>&1; then
    tail -50 "log_dump_${format}"
    echo "FAILED: dumping the DAOD_${format}"
    exit 1
  fi
  echo "DAOD_${format}: $(wc -l < "dump_${format}.txt") lines dumped"
done
# Every collection must have about the size it has in ATLAS's release (derivation_dump_sizes.txt), on
# every platform: this catches a job that runs but reconstructs much less where the dumps
# cannot be compared exactly (macOS).
if ! python "${here}/dump_counts.py" "${here}/derivation_dump_sizes.txt" dump_PHYS.txt dump_PHYSLITE.txt; then
  exit 1
fi
# The references are per platform: ATLAS's release itself writes different floating point
# numbers on x86_64 and aarch64. ATLAS has no release for macOS to compare with.
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  platform=linux-64 ;;
  Linux-aarch64) platform=linux-aarch64 ;;
  *)             platform=$(uname -s)-$(uname -m) ;;
esac
if [ ! -f "${here}/derivation_dumps.${platform}.sha256" ]; then
  echo "no references for ${platform}: the dumps are compared only in size"
  exit 0
fi
# Each dump must have one of the sums listed for it: ATLAS's, and on linux-64 also this
# build's, which differs from ATLAS's in a few numbers (the file says which).
status=0
for name in $(grep -v '^#' "${here}/derivation_dumps.${platform}.sha256" | awk '{print $2}' | sort -u); do
  sum=$(sha256sum "${name}" | cut -d' ' -f1)
  if grep -qx "${sum}  ${name}" "${here}/derivation_dumps.${platform}.sha256"; then
    echo "${name}: OK"
  else
    echo "${name}: FAILED (${sum})"
    status=1
  fi
done
exit ${status}
