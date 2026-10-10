"""Read a POOL file (HITS, RDO, ESD) in Athena, dump every object in it and, optionally, copy it.

    python pool_rw.py <input file> <dump file> [<output file> [<events>]]

The dump is PyDumper's (ATLAS's test of its event data classes). The geometry is built from
the input's geometry tag (the dumpers decode identifiers and positions). The copy is a stream
that takes every event object from the input, with the input's metadata propagated, except
the trigger menu: its metadata tool (xAODTriggerCnv) comes with the trigger decision
packages, in a later layer.
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
flags.Exec.MaxEvents = int(sys.argv[4]) if len(sys.argv) > 4 else -1
flags.lock()

acc = MainServicesCfg(flags)
acc.merge(PoolReadCfg(flags))
acc.merge(DumpCfg(flags, dump))

if outfile:
    from OutputStreamAthenaPool.OutputStreamConfig import OutputStreamCfg
    from xAODMetaDataCnv.InfileMetaDataConfig import SetupMetaDataForStreamCfg

    flags = flags.clone()
    flags.addFlag("Output.TESTFileName", outfile)
    flags.addFlag("Output.doWriteTEST", True)
    flags.Input.MetadataItems = {
        k: v for k, v in flags.Input.MetadataItems.items() if "TriggerMenu" not in k
    }
    flags.lock()
    acc.merge(OutputStreamCfg(flags, "TEST", takeItemsFromInput=True))
    acc.merge(SetupMetaDataForStreamCfg(flags, "TEST"))

sys.exit(acc.run().isFailure())
