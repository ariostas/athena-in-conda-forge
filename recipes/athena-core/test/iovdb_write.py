# ATLAS's IOVDbTestAlgWriteCool test (AtlasTest/DatabaseTest/IOVDbTestAlg): conditions objects
# written to a POOL file (SimplePoolFile.root) and registered in a COOL SQLite database
# (mytest.db).
import os
import sys

from AthenaConfiguration.Enums import LHCPeriod
from IOVDbTestAlg.IOVDbTestAlgConfig import IOVDbTestAlgFlags, IOVDbTestAlgWriteCfg

flags = IOVDbTestAlgFlags()
# The LHC run is otherwise deduced from the geometry tag, with the geometry database
# (AtlasGeoModel, a later layer).
flags.GeoModel.Run = LHCPeriod.Run3
flags.Exec.MaxEvents = 25
flags.lock()

acc = IOVDbTestAlgWriteCfg(flags, registerIOV=True)
for f in ("mytest.db", "SimplePoolFile.root"):
    if os.path.exists(f):
        os.remove(f)
sys.exit(acc.run(flags.Exec.MaxEvents).isFailure())
