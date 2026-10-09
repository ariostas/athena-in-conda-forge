#!/bin/bash
# Run ATLAS's T/P converter tests of this layer (tpcnv_tests.txt) as ATLAS's run_tpcnv_test
# does: the job must succeed, and its log must have none of the error patterns of ATLAS's
# noerror.sh (the dump differing from the reference is one of them). They read their input
# files and references from CVMFS, so they are skipped without it. Some also need the network.
set -euo pipefail

DATA=/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art
if [ ! -d "${DATA}" ]; then
  echo "SKIPPED: ${DATA} is not available"
  exit 0
fi
here=$(cd "$(dirname "$0")" && pwd)
# Some tests read the geometry database (through ATLAS's public Frontier server) and
# conditions payloads, as the geometry test of athena-detdescr does.
export FRONTIER_SERVER=${FRONTIER_SERVER:-"(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)"}
export ATLAS_POOLCOND_PATH=${ATLAS_POOLCOND_PATH:-/cvmfs/atlas-condb.cern.ch/repo/conditions}

run_one() {
  local pkg=$1 test=$2 tag=$3
  mkdir -p "tpcnv/${test}"
  cd "tpcnv/${test}"
  local status=0
  ATLAS_REFERENCE_TAG=${tag} "${test}_test.py" > log 2>&1 || status=$?
  if [ "${status}" != 0 ] ||
      grep -Ea "^ERROR | ERROR |^FATAL | FATAL | WARNING\s*FPE|runtime error:" log > errors; then
    echo "FAILED ${test} (${pkg}, exit code ${status}):"
    head -50 errors 2>/dev/null || true
    tail -30 log
    return 1
  fi
  echo "ok ${test}"
}
export -f run_one

grep -v '^#' "${here}/tpcnv_tests.txt" |
  xargs -P "${CPU_COUNT:-4}" -L 1 bash -c 'run_one "$0" "$1" "$2"'
echo "all T/P converter tests passed"
