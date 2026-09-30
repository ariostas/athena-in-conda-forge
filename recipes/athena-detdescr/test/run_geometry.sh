#!/bin/bash
# The ATLAS Run 3 geometry built in Athena from the geometry database and dumped to a GeoModel
# SQLite file with DumpGeo, then read back and written again by GeoModel's gmcat.
#
# The geometry database and the conditions it needs are read through Frontier, as asetup sets
# it up for ATLAS users, and the conditions payloads from CVMFS: without CVMFS, the test is
# skipped. (PLAN.md D6: a default FRONTIER_SERVER for conda users needs ATLAS's agreement.)
set -euo pipefail
if [ ! -d /cvmfs/atlas-condb.cern.ch/repo/conditions ]; then
  echo "run_geometry.sh: no ATLAS CVMFS, skipped"
  exit 0
fi
export FRONTIER_SERVER=${FRONTIER_SERVER:-"(serverurl=http://atlasfrontier-ai.cern.ch:8000/atlr)"}
export ATLAS_POOLCOND_PATH=${ATLAS_POOLCOND_PATH:-/cvmfs/atlas-condb.cern.ch/repo/conditions}

log=dumpgeo.log
db=geometry.db
rm -f "${db}"
if ! python -m DumpGeo.DumpGeoConfig --outFilename="${db}" > "${log}" 2>&1; then
  tail -100 "${log}"
  exit 1
fi
# the detector managers dumped, and the final message
sed -n '/Detector Managers that are being dumped/,/Creating the SQLite/p' "${log}" | grep -v "treetop:"
grep "Geometry saved" "${log}"
gmcat "${db}" -o copy.db > gmcat.log 2>&1 || { cat gmcat.log; exit 1; }
python - "${db}" copy.db <<'PY'
import sqlite3, sys
# What ATLAS's own 25.0.73 (CVMFS, aarch64) dumps for the same job: the whole Run 3 detector.
reference = {"PhysVols": 58181, "FullPhysVols": 26226, "LogVols": 59048, "Materials": 485}
for db in sys.argv[1:]:
    c = sqlite3.connect(db)
    n = {t: c.execute(f"select count(*) from {t}").fetchone()[0] for t in reference}
    print(db, n)
    assert n == reference, f"{db}: {n}, ATLAS's release: {reference}"
PY
