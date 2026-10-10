#!/bin/bash
# Analyses with ATLAS's CP algorithms (CPRun.py and a YAML configuration), each n-tuple dumped
# as text (dump_ntuple.py) and checked against the one ATLAS's own release writes:
# - the Open Data file (2015 data, DAOD_PHYSLITE, CC0) with opendata_data15.yaml; the
#   reference dump is opendata_data15.dump.xz. The calibration files (GroupData) come from
#   CVMFS if it is mounted, otherwise from ATLAS's web server: this needs no CVMFS;
# - with CVMFS, two of ATLAS's own CP algorithm tests (AnalysisAlgorithmsConfig), on its MC
#   test files (licence unclear, read in place): TestCPRunFullSim (DAOD_PHYS, every object
#   with its systematic variations, scale factors and truth; its dump's sha256 sum is in
#   cp_dumps.sha256) and TestCPRunPhysliteLikePhyslite (DAOD_PHYSLITE, 4 threads, no n-tuple:
#   it must run without errors).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# The configuration looks the LHC period of the input's geometry tag up in the geometry
# database: through ATLAS's public Frontier server.
export FRONTIER_SERVER=${FRONTIER_SERVER:-"(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)"}
opendata=${1:-${PWD}/opendata/DAOD_PHYSLITE.37001701._000001.pool.root.1}

# What ATLAS's tests check in a job's log (noerror.sh)
noerror() {
  if grep -Ea -e "^ERROR | ERROR |^FATAL | FATAL | WARNING\s*FPE|runtime error:" "$1"; then
    echo "FAILED: errors in $1"
    exit 1
  fi
}

cprun() {
  local name=$1
  shift
  mkdir -p "cp/${name}"
  cd "cp/${name}"
  if ! CPRun.py -o "${name}" "$@" > log 2>&1; then
    tail -50 log
    echo "FAILED: CPRun.py $*"
    exit 1
  fi
  noerror log
  cd ../..
}

dump() {
  local name=$1
  python "${here}/dump_ntuple.py" "cp/${name}.txt" "cp/${name}/${name}.root" "cp/${name}/hist-${name}.root"
  echo "${name}: $(grep -m1 '^TTree' "cp/${name}.txt")"
}

cprun opendata -i "${opendata}" -t "${here}/opendata_data15.yaml"
dump opendata
python - "${here}/opendata_data15.dump.xz" cp/opendata.txt <<'PY'
import difflib, lzma, sys
ref = lzma.open(sys.argv[1], "rt").read().splitlines()
out = open(sys.argv[2]).read().splitlines()
if out != ref:
    sys.stdout.writelines(
        l + "\n" for l in list(difflib.unified_diff(ref, out, "reference", sys.argv[2], lineterm=""))[:100]
    )
    sys.exit(f"{sys.argv[2]} differs from the reference dump")
print(f"{sys.argv[2]}: {len(out)} lines, identical to the reference")
PY

# ATLAS's test files (Asg_Test: ASG_TEST_FILE_MC, ASG_TEST_FILE_LITE_RUN3_MC)
if [ ! -f "${ASG_TEST_FILE_MC}" ]; then
  echo "SKIPPED: ATLAS's CP algorithm tests (${ASG_TEST_FILE_MC} is not available)"
  exit 0
fi
export ATLAS_POOLCOND_PATH=${ATLAS_POOLCOND_PATH:-/cvmfs/atlas-condb.cern.ch/repo/conditions}
cprun fullsim -i "${ASG_TEST_FILE_MC}" -t AnalysisAlgorithmsConfig/test_configuration_Run2.yaml -e 150
dump fullsim
cprun physlite -i "${ASG_TEST_FILE_LITE_RUN3_MC}" \
  -t AnalysisAlgorithmsConfig/test_configuration_physlite_like.yaml -e 1000 --test-mt-dependencies 4
grep "accepted 1000 out of 1000 events" cp/physlite/log
(cd cp && sha256sum -c "${here}/cp_dumps.sha256")
