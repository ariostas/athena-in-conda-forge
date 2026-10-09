"""Read an xAOD file (AOD or DAOD) in Athena, dump every object in it and, optionally, copy it.

    python xaod_rw.py <input file> <dump file> [<output file>]

The dump is PyDumper's (ATLAS's test of its event data classes). The copy is a DAOD_TEST
stream that takes every event object from the input, with the input's metadata propagated
the way a derivation job does it, except the trigger menu: its metadata tool (xAODTriggerCnv)
comes with the trigger decision packages, in a later layer.
"""

import sys

from AthenaConfiguration.AllConfigFlags import initConfigFlags
from AthenaConfiguration.MainServicesConfig import MainServicesCfg
from AthenaPoolCnvSvc.PoolReadConfig import PoolReadCfg
from PyDumper.DumpConfig import DumpCfg

infile, dump = sys.argv[1:3]
outfile = sys.argv[3] if len(sys.argv) > 3 else None

flags = initConfigFlags()
flags.Input.Files = [infile]
flags.Exec.MaxEvents = -1
# PyDumper builds the geometry when the input names one; xAOD objects do not need it.
flags.GeoModel.AtlasVersion = ""
flags.lock()

acc = MainServicesCfg(flags)
acc.merge(PoolReadCfg(flags))
acc.merge(DumpCfg(flags, dump))

if outfile:
    from OutputStreamAthenaPool.OutputStreamConfig import OutputStreamCfg
    from xAODMetaDataCnv.InfileMetaDataConfig import SetupMetaDataForStreamCfg

    flags = flags.clone()
    flags.addFlag("Output.DAOD_TESTFileName", outfile)
    flags.addFlag("Output.doWriteDAOD_TEST", True)
    flags.Input.MetadataItems = {
        k: v for k, v in flags.Input.MetadataItems.items() if "TriggerMenu" not in k
    }
    flags.lock()
    acc.merge(OutputStreamCfg(flags, "DAOD_TEST", takeItemsFromInput=True))
    acc.merge(SetupMetaDataForStreamCfg(flags, "DAOD_TEST"))

sys.exit(acc.run().isFailure())
