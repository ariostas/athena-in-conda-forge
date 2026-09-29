"""The existing ATLAS projects (AnalysisBase, AthAnalysis, AthGeneration, AthSimulation,
DetCommon, VP1Light, Athena) as candidate layer boundaries.

    python3 athena-notes/analysis/scripts/projects.py

Inputs in _work/projects/: <Project>.package_filters.txt (from athena at the 25.0.73 commit)
and <Project>.packages.txt (from the installed releases on CVMFS). For each project it
reports: package count, how the filter reproduces packages.txt, nesting with the others,
TUs when built in the project's own mode (XAOD_STANDALONE / XAOD_ANALYSIS / SIMULATIONBASE /
GENERATIONBASE) and in Athena mode, and how many packages the Athena-mode dependency closure
adds (i.e. is the project closed under Athena's dependencies, so usable as an Athena layer).
Writes _work/projects.json {project: [packages]}.
"""

import copy
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cmakeparse as cp  # noqa: E402
import depgraph  # noqa: E402
import graph  # noqa: E402
from scan import WORK  # noqa: E402

P = os.path.join(WORK, "projects")
MODES = {
    "AnalysisBase": {"XAOD_STANDALONE": "1", "XAOD_ANALYSIS": "1"},
    "ColumnarAnalysis": {
        "XAOD_STANDALONE": "1",
        "XAOD_ANALYSIS": "1",
        "COLUMNAR_ANALYSIS": "1",
    },
    "AthAnalysis": {"XAOD_ANALYSIS": "1"},
    "AthGeneration": {"GENERATIONBASE": "1"},
    "AthSimulation": {"SIMULATIONBASE": "1"},
    "DetCommon": {},
    "VP1Light": {"BUILDVP1LIGHT": "1", "XAOD_STANDALONE": "1", "XAOD_ANALYSIS": "1"},
    "Athena": {},
}
ORDER = [
    "DetCommon",
    "AnalysisBase",
    "AthAnalysis",
    "AthGeneration",
    "AthSimulation",
    "VP1Light",
    "Athena",
]


def read_filters(name):
    rules = []
    fn = os.path.join(P, f"{name}.package_filters.txt")
    if not os.path.exists(fn):
        return None
    with open(fn) as f:
        for ln in f:
            m = re.match(r"^\s*([+-])\s+(\S+)", ln)
            if m:
                rules.append((m.group(1), re.compile("^" + m.group(2) + "$")))
    return rules


def selected(rules, pkg):
    for sign, rx in rules:
        if rx.match(pkg):
            return sign == "+"
    return True


def read_list(name):
    fn = os.path.join(P, f"{name}.packages.txt")
    if not os.path.exists(fn):
        return None
    with open(fn) as f:
        return {ln.split()[0] for ln in f if ln.strip() and not ln.startswith("#")}


def main():
    texts, files = depgraph.load()
    with open(os.path.join(WORK, "graph.json")) as f:
        g = json.load(f)
    athena = set(texts)
    universe = set(athena)
    for n in ORDER:
        lst = read_list(n)
        if lst:
            universe |= lst
    sets = {}
    print(f"universe (Athena packages + other projects' packages): {len(universe)}")
    for n in ORDER:
        rules = read_filters(n)
        lst = read_list(n) if n != "Athena" else athena
        fsel = {p for p in universe if selected(rules, p)} if rules else None
        if lst is not None:
            sets[n] = lst
            extra = ""
            if fsel is not None:
                extra = (
                    f"; filter on universe selects {len(fsel)}, "
                    f"{len(fsel - lst)} not in packages.txt, {len(lst - fsel)} missing"
                )
            print(f"{n}: packages.txt {len(lst)}{extra}")
        else:
            sets[n] = fsel
            print(f"{n}: (no release on CVMFS) filter selects {len(fsel)}")
    with open(os.path.join(WORK, "projects.json"), "w") as f:
        json.dump({k: sorted(v) for k, v in sets.items()}, f, indent=1)

    print("\nnesting: row ⊂ column? (count of row packages NOT in column)")
    print(f"{'':>14}" + "".join(f"{c:>14}" for c in ORDER))
    for r in ORDER:
        print(f"{r:>14}" + "".join(f"{len(sets[r] - sets[c]):>14}" for c in ORDER))

    print(
        "\nnot in Athena:",
        {n: sorted(sets[n] - athena) for n in ORDER if n != "Athena"},
    )

    print("\ncost and closure (Athena packages only):")
    for n in ORDER:
        s = sets[n] & athena
        cfg = copy.deepcopy(cp.ATHENA_CONFIG)
        cfg["vars"].update(MODES[n])
        sub = {p: texts[p] for p in s}
        own, _ = depgraph.analyse(sub, files, cfg)
        own_tus = sum(
            len(t["tus"]) + t["gen_tus"]
            for d in own.values()
            for t in d["targets"]
            if t["kind"] != "test"
        )
        ath_tus = sum(g[p]["tus"] + g[p]["gen_tus"] for p in s)
        test_tus = sum(g[p]["test_tus"] for p in s)
        clo = graph.closure(g, s)
        clo_t = graph.closure(g, s, "deps_test")
        ext = set()
        for p in clo:
            ext |= set(g[p]["externals"])
        groups = sorted(graph.group_of(ext))
        print(
            f"  {n:>13}: {len(s)} pkgs; build TUs own-mode {own_tus}, Athena-mode {ath_tus} "
            f"(+{test_tus} test); Athena-mode closure adds {len(clo - s)} pkgs "
            f"({sum(g[p]['tus'] + g[p]['gen_tus'] for p in clo - s)} TUs), with tests "
            f"{len(clo_t - s)}; heavy externals: {groups}"
        )
        if 0 < len(clo - s) <= 40:
            print("      added:", sorted(clo - s))


if __name__ == "__main__":
    main()
