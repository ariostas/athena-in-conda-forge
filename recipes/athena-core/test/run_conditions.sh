#!/bin/bash
# Conditions data: write with IOVDbTestAlg (payloads in a POOL file, IOVs in a COOL SQLite
# database), then read back through IOVDbSvc.
set -euo pipefail
here=$(dirname "$0")
run() {
  local log=$1
  shift
  if ! "$@" > "${log}" 2>&1; then
    cat "${log}"
    exit 1
  fi
}
run iovdb_write.log python "${here}/iovdb_write.py"
test -s mytest.db
test -s SimplePoolFile.root
run iovdb_read.log python "${here}/iovdb_read.py"
# one printout per event, with the values iovdb_write.py stored (as in ATLAS's reference log)
test "$(grep -c "^IOVDbTestAlg .*INFO in printCondObjects()" iovdb_read.log)" = 30
grep -m1 "IOVDbTestAlg .*Found mdt element map run 0 event 0 time  45 channel 1 iov" iovdb_read.log
grep -m1 "IOVDbTestAlg .*Found amdb correction trans 1 2 3 rot 4 5 6" iovdb_read.log
grep -m1 -F "ChanNum 36 Attribute list [xPosition (float) : 55], [id (int) : 37]" iovdb_read.log
