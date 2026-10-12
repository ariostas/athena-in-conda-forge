#!/bin/bash
# GroupData through PathResolver, with CALIBPATH from PathResolver's environment and downloads
# enabled by groupdata-activate.sh: a file from CVMFS if it is mounted, and the same file
# downloaded from ATLAS's web server; a file that is on neither (one of the web servers answers
# 404) gives no result and leaves nothing behind (patch 0004).
set -euo pipefail

GRL=GoodRunsLists/data15_13TeV/20170619/data15_13TeV.periodAllYear_DetStatus-v89-pro21-02_Unknown_PHYS_StandardGRL_All_Good_25ns.xml
SHA256=f1baf9be0a13c2fdf08a5d41632eca5577ac074b0aa091d8adbec2e78a4f005f
MISSING=GoodRunsLists/no-such-file.xml

case ":${CALIBPATH}:" in
  *:http//cern.ch/atlas-groupdata:*) ;;
  *) echo "FAILED: CALIBPATH has no GroupData: ${CALIBPATH}"; exit 1 ;;
esac
[ "${PATHRESOLVER_ALLOWHTTPDOWNLOAD:-}" = 1 ] || { echo "FAILED: downloads not enabled"; exit 1; }

find_calib() {
  python -c 'import sys; from PathResolver import PathResolver; print(PathResolver.FindCalibFile(sys.argv[1]))' "$1" | tail -1
}

if [ -d /cvmfs/atlas.cern.ch/repo/sw/database/GroupData ]; then
  found=$(find_calib "${GRL}")
  [ "${found}" = "/cvmfs/atlas.cern.ch/repo/sw/database/GroupData/${GRL}" ] || { echo "FAILED: found ${found}"; exit 1; }
  echo "from CVMFS: ${found}"
fi

# the web server only
mkdir -p groupdata
cd groupdata
CALIBPATH=$(tr ':' '\n' <<< "${CALIBPATH}" | grep -v '^/cvmfs/' | paste -sd: -)
export CALIBPATH
found=$(find_calib "${GRL}")
# downloaded to the working directory
[ -n "${found}" ] && [ "$(realpath "${found}")" = "${PWD}/${GRL}" ] || { echo "FAILED: found ${found}"; exit 1; }
echo "${SHA256}  ${GRL}" | sha256sum -c
found=$(find_calib "${MISSING}")
[ -z "${found}" ] || { echo "FAILED: found ${found}"; exit 1; }
[ ! -e "${MISSING}" ] || { echo "FAILED: ${MISSING} left behind"; exit 1; }
echo "${MISSING}: not found, nothing left behind"
