#!/bin/bash
# The Athena developer loop, as on top of a CVMFS release: a work area with ATLAS's WorkDir
# project and a package from the athena repository (here the recipe's source: WorkDir and
# AthExHelloWorld), the package changed, built against the installed release, and the change
# visible to athena.py once the work area's setup.sh is sourced.
set -euo pipefail

mkdir -p ws/athena/Projects ws/athena/Control/AthenaExamples
cp -r Projects/WorkDir ws/athena/Projects/
cp -r Control/AthenaExamples/AthExHelloWorld ws/athena/Control/AthenaExamples/
sed -i.orig 's/my message to the world/my message from a conda work area/' \
  ws/athena/Control/AthenaExamples/AthExHelloWorld/src/HelloTool.cxx
rm ws/athena/Control/AthenaExamples/AthExHelloWorld/src/HelloTool.cxx.orig

cd ws
if ! cmake -S athena/Projects/WorkDir -B build > cmake.log 2>&1; then
  cat cmake.log
  echo "FAILED: configuring the work area"
  exit 1
fi
if ! cmake --build build > build.log 2>&1; then
  tail -100 build.log
  echo "FAILED: building the work area"
  exit 1
fi
set +eu
# shellcheck disable=SC1090
source build/*/setup.sh
set -eu
if ! athena.py AthExHelloWorld/HelloWorldConfig.py > hello.log 2>&1; then
  cat hello.log
  echo "FAILED: athena.py"
  exit 1
fi
grep "HelloWorld.HelloTool .*my message from a conda work area: Hello World!" hello.log
grep "leaving with code 0" hello.log
