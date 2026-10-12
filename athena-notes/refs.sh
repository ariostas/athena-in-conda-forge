#!/bin/bash
# refs.sh [<recipe>/test/<script> ...]: run the layers' reference-checked tests in ATLAS's own
# release from CVMFS (athena-ref, or athena-ref-amd64 for x86_64), to see whether ATLAS's
# outputs on this platform match the references the tests hold. Each test runs in
# /work/refs/<recipe>/ (log: test.log), its exit code goes to /work/refs/summary.txt.
# Needs a copy of recipes/ in /work/tmp/recipes, cvmfs-athena.sh in /work/tmp, and the Open
# Data file of the edm and analysis tests in /work/refs/opendata/.
tests=("$@")
if [ ${#tests[@]} -eq 0 ]; then
  tests=(athena-reco-tracking/test/run_tracking.sh athena-edm-det/test/run_pool.sh
         athena-analysis/test/run_cp.sh athena-edm/test/run_xaod.sh
         athena-trigger/test/run_trigger.sh athena-reco/test/run_reco.sh
         athena-rest/test/run_derivation.sh athena-sim/test/run_sim.sh)
fi
for t in "${tests[@]}"; do
  name=${t%%/*}
  rm -rf "/work/refs/${name}"
  mkdir -p "/work/refs/${name}"
  cd "/work/refs/${name}" || exit 1
  ln -s /work/refs/opendata opendata
  bash /work/tmp/cvmfs-athena.sh bash "/work/tmp/recipes/${t}" > test.log 2>&1
  echo "${name} rc=$?" >> /work/refs/summary.txt
done
echo done >> /work/refs/summary.txt
