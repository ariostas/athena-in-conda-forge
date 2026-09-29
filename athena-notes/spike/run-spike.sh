#!/bin/bash
# Run the whole stacking spike in order: CORAL, the small externals and Gaudi into the host env,
# the stub AthenaExternals, then three Athena layers, the top one named "Athena".
# Run inside the athena-dev container; logs go to /work/logs/spike-<step>.log.
set -euo pipefail
S=/repo/athena-notes/spike
mkdir -p /work/logs
step() {
  local name=$1
  shift
  echo ">> ${name}"
  if ! "$@" > "/work/logs/spike-${name}.log" 2>&1; then
    echo "   FAILED, see /work/logs/spike-${name}.log"
    tail -30 "/work/logs/spike-${name}.log"
    exit 1
  fi
  tail -1 "/work/logs/spike-${name}.log"
}

# STEPS: which steps to run (default all).
want() { [ -z "${STEPS:-}" ] || [[ " ${STEPS} " == *" $1 "* ]]; }

[ "${SKIP_EXTERNALS:-0}" = 1 ] || {
  want coral && step coral bash $S/build-coral.sh
  want extras && step extras bash $S/build-extras.sh
  want gaudi && step gaudi bash $S/build-gaudi.sh
}
want externals && step externals bash $S/build-externals.sh
want layer1 && step layer1 bash $S/build-layer.sh AthSpikeBase AthenaExternals \
  AtlasTest/TestTools Control/SGCore Control/CxxUtils Control/AthAllocators \
  Control/RootUtils Control/DataModelRoot Control/AthenaKernel Control/CLIDComps
want layer2 && step layer2 bash $S/build-layer.sh AthSpikeEvent AthSpikeBase \
  Control/SGTools Control/AthContainersInterfaces Control/AthLinks \
  Database/PersistentDataModel Control/AthContainers Control/StoreGate \
  Event/xAOD/xAODCore Event/xAOD/xAODEventInfo
want layer3 && step layer3 bash $S/build-layer.sh Athena AthSpikeEvent \
  Control/AthenaBaseComps Control/AthenaExamples/AthExHelloWorld \
  Control/AthContainersRoot Control/AthenaAuditors Control/AthenaCommon \
  Control/AthenaConfiguration Control/AthenaInterprocess Control/AthenaMP \
  Control/AthenaMPTools Control/AthenaPython Control/AthenaServices \
  Control/PerformanceMonitoring/PerfMonComps Control/PerformanceMonitoring/PerfMonKernel \
  Control/SGComps Database/AthenaPOOL/AthenaPoolUtilities Database/AthenaRoot/RootAuxDynIO \
  Database/IOVDbDataModel Database/IOVDbMetaDataTools Database/SQLiteDBSvc \
  Event/EventInfo Event/EventInfoMgt Event/EventInfoUtils Generators/McEventSelector \
  Control/GaudiSequencer Database/APR/CollectionSvc Generators/GeneratorConfig Tools/Campaigns \
  Tools/PyJobTransforms Tools/PyUtils Control/AthToolSupport/AsgMessaging \
  Control/AthToolSupport/AsgTools Database/APR/StorageSvc Database/AthenaPOOL/PoolSvc \
  Tools/PathResolver
