#!/bin/bash
# ATLAS's Run 3 detector simulation with its simulation transform, Sim_tf.py, as ATLAS's
# ISF_ValidationMT test_RUN3_FullG4MT_QS_ttbar_MT runs it (FullG4MT_QS, the production
# simulator, MC23e conditions), on the first 3 events of ATLAS's ttbar EVNT test file (CVMFS,
# read in place: its licence is unclear), serially. The job reads the geometry database and
# conditions through ATLAS's public Frontier server, and the Geant4 data sets from the
# geant4-data-* packages. The HITS file is dumped with PyDumper and compared with a summary of
# the dump from ATLAS's release (compare_sim.py): the generator-level truth after the beam
# spot smearing must be identical, and every detector's hits must be there in the same amounts.
# Geant4's showers are not identical to the release's (see the README), and Geant4 raises
# floating point exceptions here that it does not in ATLAS's release: the log check leaves
# them out.
set -euo pipefail

EVNT=/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art/CampaignInputs/mc21/EVNT/mc21_13p6TeV.601229.PhPy8EG_A14_ttbar_hdamp258p75_SingleLep.evgen.EVNT.e8453/EVNT.29328277._003902.pool.root.1
if [ ! -f "${EVNT}" ]; then
  echo "SKIPPED: ${EVNT} is not available"
  exit 0
fi
here=$(cd "$(dirname "$0")" && pwd)
export FRONTIER_SERVER=${FRONTIER_SERVER:-"(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)"}
export ATLAS_POOLCOND_PATH=${ATLAS_POOLCOND_PATH:-/cvmfs/atlas-condb.cern.ch/repo/conditions}

# What ATLAS's tests check in a job's log (noerror.sh)
noerror() {
  if grep -Ea -e "^ERROR | ERROR |^FATAL | FATAL |runtime error:" "$1"; then
    echo "FAILED: errors in $1"
    exit 1
  fi
}

mkdir -p sim
cd sim
# AthenaConfiguration.TestDefaults: defaultConditionsTags.RUN3_MC, defaultGeometryTags.RUN3
if ! Sim_tf.py --CA --conditionsTag "default:OFLCOND-MC23-SDR-RUN3-11-02" \
    --geometryVersion "default:ATLAS-R3S-2021-03-02-00" --simulator FullG4MT_QS \
    --postInclude PyJobTransforms.UseFrontier \
    --preInclude 'EVNTtoHITS:Campaigns.MC23eSimulationMultipleIoV' \
    --inputEVNTFile "${EVNT}" --outputHITSFile HITS.pool.root \
    --maxEvents 3 --jobNumber 1 --imf False > log 2>&1; then
  tail -50 log
  tail -50 log.EVNTtoHITS || true
  echo "FAILED: Sim_tf.py"
  exit 1
fi
noerror log.EVNTtoHITS
if ! python "${here}/pool_rw.py" HITS.pool.root dump_HITS.txt > log_dump 2>&1; then
  tail -50 log_dump
  echo "FAILED: dumping the HITS"
  exit 1
fi
echo "HITS: $(wc -l < dump_HITS.txt) lines dumped"
python "${here}/compare_sim.py" check dump_HITS.txt "${here}/sim_reference.json"
