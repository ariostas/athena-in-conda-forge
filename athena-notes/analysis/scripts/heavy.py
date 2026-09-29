"""Which translation units reach heavy external headers (Acts, Eigen, Geant4, ...), and how many
Athena headers each TU pulls in -- a proxy for relative compile cost per package/layer.

    python3 athena-notes/analysis/scripts/heavy.py [--top 30]

Follows quoted and angle includes through Athena's own headers (resolved via the public
header directories, and relative to the including file), and classifies the first
unresolved external include of each kind. Writes _work/heavy.json
{package: {"tus": n, "hdrs_mean": x, "reach": {"Acts": n, ...}}}.
Needs _work/includes.json (includes.py).
"""

import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import depgraph  # noqa: E402
from scan import WORK  # noqa: E402

EXT = [
    ("Acts", re.compile(r"^(Acts|ActsPlugins|ActsFatras|detray|traccc)/")),
    ("Eigen", re.compile(r"^(Eigen|unsupported/Eigen)/")),
    ("Geant4", re.compile(r"^(G4\w+\.hh|Geant4/|G4\w+\.icc)")),
    (
        "GeoModel",
        re.compile(r"^(GeoModel\w*|GeoGenericFunctions|GeoMaterial2G4|GeoModel2G4)/"),
    ),
    ("Gaudi", re.compile(r"^Gaudi\w*/")),
    ("Boost", re.compile(r"^boost/")),
    ("ROOT", re.compile(r"^(T[A-Z]\w*\.h|R[A-Z]\w*\.h|ROOT/|Math/|RooFit|Roo\w+\.h)")),
    (
        "tdaq",
        re.compile(
            r"^(eformat|ers|owl|is|oh|ipc|CTPfragment|dqm_core|hltinterface|"
            r"L1CTP|coca|TTCInfo|rc)/"
        ),
    ),
    (
        "CORAL/COOL",
        re.compile(
            r"^(CoralBase|RelationalAccess|CoolKernel|CoolApplication|"
            r"CoralKernel)/"
        ),
    ),
    ("onnx", re.compile(r"^(onnxruntime|core/session|lwtnn)/")),
    ("FastJet", re.compile(r"^fastjet/")),
    ("HepMC3", re.compile(r"^HepMC3/")),
    ("CLHEP", re.compile(r"^CLHEP/")),
    ("Qt/Coin", re.compile(r"^(Q[A-Z]\w*|Qt\w*/|Inventor/)")),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=30)
    a = ap.parse_args()
    texts, files = depgraph.load()
    pfiles = depgraph.package_files(texts, files)
    with open(os.path.join(WORK, "pkgs.json")) as f:
        pkgs = json.load(f)
    with open(os.path.join(WORK, "includes.json")) as f:
        inc = json.load(f)
    # full path (pkg/file) -> includes
    incl = {}
    for p, rec in inc.items():
        for f, lst in rec.items():
            incl[p + "/" + f] = lst
    # "Dir/rest" -> full path, for public header dirs
    pub = {}
    for p, fl in pfiles.items():
        for f in fl:
            if "/" in f:
                pub.setdefault(f, p + "/" + f)
    memo = {}

    def resolve(cur, i):
        d = os.path.dirname(cur)
        cand = os.path.normpath(os.path.join(d, i))
        if cand in incl:
            return cand
        if i in pub and pub[i] in incl:
            return pub[i]
        return None

    def reach(path):
        """(set of Athena headers, set of external kinds) reached from path."""
        if path in memo:
            return memo[path]
        memo[path] = (frozenset(), frozenset())  # cycle guard
        hs = set()
        ks = set()
        for i in incl.get(path, ()):
            r = resolve(path, i)
            if r:
                hs.add(r)
                h2, k2 = reach(r)
                hs |= h2
                ks |= k2
            else:
                for k, rx in EXT:
                    if rx.search(i):
                        ks.add(k)
                        break
        memo[path] = (frozenset(hs), frozenset(ks))
        return memo[path]

    sys.setrecursionlimit(20000)
    out = {}
    for p, d in pkgs.items():
        tus = sorted({f for t in d["targets"] if t["kind"] != "test" for f in t["tus"]})
        r = collections.Counter()
        hsum = 0
        for f in tus:
            hs, ks = reach(p + "/" + f)
            hsum += len(hs)
            r.update(ks)
        out[p] = {
            "tus": len(tus),
            "hdrs_mean": hsum / len(tus) if tus else 0,
            "reach": dict(r),
        }
    with open(os.path.join(WORK, "heavy.json"), "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    tot = collections.Counter()
    n = 0
    for v in out.values():
        tot.update(v["reach"])
        n += v["tus"]
    print(f"{n} TUs; fraction reaching each external kind:")
    for k, c in tot.most_common():
        print(f"   {k:>12}: {c:6d} ({100 * c / n:.0f}%)")
    print("heaviest packages by mean Athena headers per TU:")
    for p, v in sorted(out.items(), key=lambda x: -x[1]["hdrs_mean"])[: a.top]:
        print(f"   {v['hdrs_mean']:7.0f} {v['tus']:4d}  {p}")


if __name__ == "__main__":
    main()
