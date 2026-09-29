# ATLAS's IOVDbTestAlgReadCool test: the conditions of iovdb_write.py read back through
# IOVDbSvc, from the SQLite database and (for the POOL payloads) from the POOL file.
import sys

from AthenaConfiguration.Enums import LHCPeriod
from IOVDbTestAlg.IOVDbTestAlgConfig import IOVDbTestAlgFlags, IOVDbTestAlgReadCfg

flags = IOVDbTestAlgFlags()
# The LHC run is otherwise deduced from the geometry tag, with the geometry database
# (AtlasGeoModel, a later layer).
flags.GeoModel.Run = LHCPeriod.Run3
flags.Exec.MaxEvents = 30
flags.lock()

acc = IOVDbTestAlgReadCfg(flags)
acc.getService("EventSelector").EventsPerRun = 10
sys.exit(acc.run(flags.Exec.MaxEvents).isFailure())
