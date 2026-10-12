#!/bin/bash
# bg-build.sh <recipe> ...: build-local.sh, detached; exit code in /work/logs/bg-build.rc.
# CONFIG (default linux_aarch64; linux64 in athena-dev-amd64) is the .ci_support config.
# It runs a copy of build-local.sh, so that the repository's can be edited meanwhile.
export PATH=/work/tools/bin:$PATH KEEP_BUILD=${KEEP_BUILD:-1} REPO=/repo
cd /repo
rm -f /work/logs/bg-build.rc
cp athena-notes/build-local.sh /work/build-local.running.sh
bash /work/build-local.running.sh "${CONFIG:-linux_aarch64}" "$@" > /work/logs/bg-build.out 2>&1 < /dev/null
echo $? > /work/logs/bg-build.rc
