"""dqm_core's dictionaries load through their rootmaps, and its dummy algorithm, registered with
the algorithm manager when its library is loaded, assesses a histogram."""

import ROOT

for cls in ("dqm_core::Result", "dqm_core::Algorithm", "dqm_core::AlgorithmConfig"):
    c = ROOT.TClass.GetClass(cls)
    assert c and c.HasDictionary(), f"no dictionary for {cls}"

assert ROOT.gSystem.Load("libdqm_dummy") >= 0
ROOT.gInterpreter.Declare(
    '#include "dqm_core/AlgorithmManager.h"\n#include "dqm_core/test/DummyAlgorithmConfig.h"'
)
algorithm = ROOT.dqm_core.AlgorithmManager.instance().getAlgorithm("DummyAlgorithm")
config = ROOT.dqm_core.test.DummyAlgorithmConfig()
config.addParameter("status", 3)
histogram = ROOT.TH1F("h", "h", 10, 0, 1)
histogram.FillRandom("gaus", 100)
result = algorithm.execute("h", histogram, config)
print("status:", result.status_)
assert result.status_ == ROOT.dqm_core.Result.Green
