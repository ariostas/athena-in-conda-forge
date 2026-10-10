"""Inner detector tracking on an RDO file, the reconstructed tracks and vertices written to a file.

    python track_reco.py <RDO file> <output file> <events>

The job of ATLAS's own test of the tracking configuration (python -m InDetConfig.TrackRecoConfig:
a Run 3 RDO, only the inner detector), with the output that InDetTrackRecoCfg declares for an
AOD (track particles, primary vertices, ...) and the event info written to <output file>, with
the file's metadata.
"""

import sys

from AthenaConfiguration.AllConfigFlags import initConfigFlags
from AthenaConfiguration.MainServicesConfig import MainServicesCfg
from AthenaConfiguration.TestDefaults import defaultConditionsTags
from AthenaPoolCnvSvc.PoolReadConfig import PoolReadCfg
from InDetConfig.ConfigurationHelpers import OnlyTrackingPreInclude
from InDetConfig.TrackRecoConfig import InDetTrackRecoCfg
from OutputStreamAthenaPool.OutputStreamConfig import addToAOD
from xAODEventInfoCnv.xAODEventInfoCnvConfig import EventInfoCnvAlgCfg
from xAODMetaDataCnv.InfileMetaDataConfig import SetupMetaDataForStreamCfg
from xAODTruthCnv.xAODTruthCnvConfig import GEN_AOD2xAODCfg

infile, outfile, events = sys.argv[1:4]

flags = initConfigFlags()
OnlyTrackingPreInclude(flags)
flags.Input.Files = [infile]
flags.IOVDb.GlobalTag = defaultConditionsTags.RUN3_MC
flags.Exec.MaxEvents = int(events)
flags.Output.AODFileName = outfile
flags.lock()

acc = MainServicesCfg(flags)
acc.merge(PoolReadCfg(flags))
if "EventInfo" not in flags.Input.Collections:
    acc.merge(EventInfoCnvAlgCfg(flags))
acc.merge(GEN_AOD2xAODCfg(flags))
acc.merge(InDetTrackRecoCfg(flags))
acc.merge(addToAOD(flags, ["xAOD::EventInfo#EventInfo", "xAOD::EventAuxInfo#EventInfoAux."]))
acc.merge(SetupMetaDataForStreamCfg(flags, "AOD"))

sys.exit(acc.run().isFailure())
