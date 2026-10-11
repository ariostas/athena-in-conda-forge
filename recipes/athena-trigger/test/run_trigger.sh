#!/bin/bash
# ATLAS's High-Level Trigger as its own trigger tests run it on simulation (TriggerJobOpts.runHLT,
# RDO to RDO_TRIG, the Dev_pp_run3_v1_TriggerValidation_prescale menu, one thread), on ATLAS's
# Run 3 RDO test file (CVMFS, read in place: its licence is unclear), on the first 5 events: the
# L1 simulation, then every HLT chain of the menu (reconstruction, hypotheses, decisions), and
# the trigger EDM written to RDO_TRIG. As in ATLAS's trigger tests, the chain counts table
# (TrigSignatureMoni: events and objects passing each step of each chain) must be identical to
# the one ATLAS's release prints (hlt_counts.ref). The job reads the geometry database and
# conditions through ATLAS's public Frontier server, and conditions payloads from CVMFS.
set -euo pipefail

RDO=/cvmfs/atlas-nightlies.cern.ch/repo/data/data-art/CampaignInputs/mc23/RDO/mc23_13p6TeV.801451.Py8EG_A3_NNPDF23LO_minbias_ND.recon.RDO.e8486_e8528_s4232_s4114_r15112/300events_RDO.39752217._004082.pool.root.1
if [ ! -f "${RDO}" ]; then
  echo "SKIPPED: ${RDO} is not available"
  exit 0
fi
here=$(cd "$(dirname "$0")" && pwd)
export FRONTIER_SERVER=${FRONTIER_SERVER:-"(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)"}
export ATLAS_POOLCOND_PATH=${ATLAS_POOLCOND_PATH:-/cvmfs/atlas-condb.cern.ch/repo/conditions}

mkdir -p trigger
cd trigger
# (the --preInclude option takes several values: it comes after the flags)
if ! python -m TriggerJobOpts.runHLT --filesInput="${RDO}" --evtMax=5 --threads=1 \
    'Trigger.triggerMenuSetup="Dev_pp_run3_v1_TriggerValidation_prescale"' \
    'IOVDb.GlobalTag="OFLCOND-MC23-SDR-RUN3-11-02"' --preInclude Campaigns.MC23a \
    > log 2>&1; then
  tail -50 log
  echo "FAILED: runHLT"
  exit 1
fi
# What ATLAS's tests check in a job's log (noerror.sh)
if grep -Ea -e "^ERROR | ERROR |^FATAL | FATAL | WARNING\s*FPE|runtime error:" log; then
  echo "FAILED: errors in the log"
  exit 1
fi
test -s RDO_TRIG.pool.root
grep "^TrigSignatureMoni " log | sed "s/^TrigSignatureMoni *INFO //" > hlt_counts.txt
if ! diff "${here}/hlt_counts.ref" hlt_counts.txt > hlt_counts.diff; then
  head -100 hlt_counts.diff
  echo "FAILED: the chain counts differ from ATLAS's release"
  exit 1
fi
echo "trigger: $(grep -c '^HLT_' hlt_counts.txt) chains counted, identical to ATLAS's release"
