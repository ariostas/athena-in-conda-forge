# A minimal Gaudi job: three empty events through a sequencer, with the random number
# service (CLHEP) and the ROOT histogram sink loaded.
from Configurables import ApplicationMgr, Gaudi__Sequencer, RndmGenSvc

ApplicationMgr(
    EvtMax=3,
    EvtSel="NONE",
    HistogramPersistency="NONE",
    TopAlg=[Gaudi__Sequencer("Seq")],
    ExtSvc=[RndmGenSvc()],
)
