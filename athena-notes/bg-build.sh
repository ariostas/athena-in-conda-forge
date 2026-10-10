#!/bin/bash
# bg-build.sh <recipe> ...: build-local.sh for linux_aarch64, detached; exit code in /work/logs/bg-build.rc
export PATH=/work/tools/bin:$PATH KEEP_BUILD=${KEEP_BUILD:-1}
cd /repo
rm -f /work/logs/bg-build.rc
./athena-notes/build-local.sh linux_aarch64 "$@" > /work/logs/bg-build.out 2>&1 < /dev/null
echo $? > /work/logs/bg-build.rc
