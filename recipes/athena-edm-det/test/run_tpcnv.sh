#!/bin/bash
# Run ATLAS's T/P converter tests of this layer (tpcnv_tests.txt) as ATLAS's run_tpcnv_test
# does: the job must succeed, and its log must have none of the error patterns of ATLAS's
# noerror.sh (the dump differing from the reference is one of them). They read their input
# files and references from CVMFS, so they are skipped without it. Some also need the network.
set -euo pipefail

# The error patterns of ATLAS's noerror.sh. On macOS, without the FPE auditor's warnings:
# conda-forge builds ROOT there with clang, which evaluates some guarded divisions anyway
# (TVector3::PseudoRapidity of a null vector computes 0/0, then discards it), so floating point
# exceptions are reported that ATLAS's release on Linux does not have.
errors_re="^ERROR | ERROR |^FATAL | FATAL | WARNING\s*FPE|runtime error:"
if [ "$(uname -s)" = Darwin ]; then
  errors_re="^ERROR | ERROR |^FATAL | FATAL |runtime error:"
fi
export errors_re

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
  mkdir -p "tpcnv/${test}/run"
  local status=0
  if [ "${tag}" = - ]; then
    # No reference tag: the reference is in the package's share/ (a source file of the
    # recipe), which ATLAS's dumper looks for in ../share.
    cp -r "${here}/../${pkg}/share" "tpcnv/${test}/"
    cd "tpcnv/${test}/run"
    "${test}_test.py" > log 2>&1 || status=$?
  else
    cd "tpcnv/${test}/run"
    ATLAS_REFERENCE_TAG=${tag} "${test}_test.py" > log 2>&1 || status=$?
  fi
  if [ "${status}" != 0 ] ||
      grep -Ea "${errors_re}" log > errors; then
    echo "FAILED ${test} (${pkg}, exit code ${status}):"
    head -50 errors 2>/dev/null || true
    tail -30 log
    return 1
  fi
  echo "ok ${test}"
}
export -f run_one
export here

grep -v '^#' "${here}/tpcnv_tests.txt" |
  xargs -P "${CPU_COUNT:-4}" -L 1 bash -c 'run_one "$0" "$1" "$2"'
echo "all T/P converter tests passed"
