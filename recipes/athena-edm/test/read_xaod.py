"""Read xAOD files in PyROOT (an xAOD transient tree) and summarise their physics objects.

    python read_xaod.py [--ref <reference summary>] <file> [<file> ...]

For each file it prints one line per container: the number of objects and the sum of one of
their quantities over all events (pT, or z for vertices, or the missing ET), and a few quantities reached through element links (the tracks of electrons
and muons, the clusters of electrons). With several files it checks that all of them have the
same summary, e.g. a DAOD and its copy written by Athena, and with --ref that it is the one in
the reference file (written with ATLAS's own release).
"""

import argparse
import sys

import ROOT

CONTAINERS = {
    "AnalysisElectrons": "pt",
    "AnalysisPhotons": "pt",
    "AnalysisMuons": "pt",
    "AnalysisTauJets": "pt",
    "AnalysisJets": "pt",
    "AnalysisLargeRJets": "pt",
    "InDetTrackParticles": "pt",
    "PrimaryVertices": "z",
    "egammaClusters": "pt",
    "MET_Core_AnalysisMET": "met",
}


def pt(obj):
    """pT of an object reached through a link, 0 for a null pointer (not "if obj": a cluster
    with no cells is false in PyROOT, through its size())."""
    return 0.0 if ROOT.addressof(obj) == 0 else obj.pt()


def summarise(fname):
    f = ROOT.TFile.Open(fname)
    tree = ROOT.xAOD.MakeTransientTree(f)
    n = tree.GetEntries()
    counts = {key: [0, 0.0] for key in CONTAINERS}
    links = {"electron tracks": 0.0, "electron clusters": 0.0, "muon tracks": 0.0}
    runs = set()
    for i in range(n):
        tree.GetEntry(i)
        runs.add(tree.EventInfo.runNumber())
        for key, quantity in CONTAINERS.items():
            for obj in getattr(tree, key):
                counts[key][0] += 1
                counts[key][1] += getattr(obj, quantity)()
        for el in tree.AnalysisElectrons:
            links["electron tracks"] += pt(el.trackParticle())
            links["electron clusters"] += pt(el.caloCluster())
        for mu in tree.AnalysisMuons:
            links["muon tracks"] += pt(mu.primaryTrackParticle())
    ROOT.xAOD.ClearTransientTrees()
    lines = [f"events {n}", f"runs {sorted(runs)}"]
    lines += [
        f"{key} {c} {CONTAINERS[key]} {s:.6g}" for key, (c, s) in counts.items()
    ]
    lines += [f"{name} {s:.6g}" for name, s in links.items()]
    return lines


def main():
    # No file access statistics sent to ATLAS's Rucio server.
    ROOT.gInterpreter.Declare('#include "xAODRootAccess/tools/TFileAccessTracer.h"')
    ROOT.xAOD.TFileAccessTracer.instance().enableDataSubmission(False)
    if not ROOT.xAOD.Init().isSuccess():
        raise RuntimeError("xAOD::Init failed")
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref")
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    results = []
    for fname in args.files:
        lines = summarise(fname)
        print(f"== {fname}")
        print("\n".join(lines))
        results.append(lines)
    if args.ref:
        with open(args.ref) as f:
            results.insert(0, f.read().splitlines())
    if any(r != results[0] for r in results[1:]):
        print("ERROR: the summaries differ")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
