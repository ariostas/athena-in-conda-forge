"""Package and target dependency graph of Athena, with externals and cycle analysis.

    python3 athena-notes/analysis/scripts/graph.py            # summary report
    python3 athena-notes/analysis/scripts/graph.py --pkg Control/AthenaKernel

Reads _work/pkgs.json and _work/targets.json (depgraph.py). Writes _work/graph.json:
{package: {"deps": [...], "deps_lib": [...], "deps_test": [...], "externals": [...],
"tus": n, "test_tus": n, "gen_tus": n}}.

Edge kinds:
  deps_lib   links of libraries (atlas_add_library/tpcnv; what other packages' code links)
  deps       links of every non-test target (libraries, components, dictionaries,
             converters, executables): what the package needs to build
  deps_test  additionally the links of its tests
"""

import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scan import WORK  # noqa: E402

LIB_KINDS = {"library", "tpcnv", "cmake_library"}
BUILD_KINDS = LIB_KINDS | {
    "component",
    "dictionary",
    "poolcnv",
    "sercnv",
    "executable",
    "reflex_dictionary",
    "root_dictionary",
}

# find_package names that are ATLAS-internal helpers, not externals.
NOT_EXTERNAL = re.compile(
    r"(Environment$|^AthenaPoolUtilitiesTest$|^xAODUtilities$|"
    r"^AtlasGeant4Utilities$|^Asg_TestEnvironment$|^Threads$|^UUID$)"
)

# Coarse external groups, used to see which layers need which heavy stacks.
GROUPS = {
    "Gaudi": {"Gaudi"},
    "tdaq": {"tdaq-common", "tdaq"},
    "CORAL/COOL/CREST": {
        "CORAL",
        "COOL",
        "Frontier_Client",
        "CrestApi",
        "Oracle",
        "cx_Oracle",
        "chai",
    },
    "GeoModel": {"GeoModel"},
    "Geant4": {"Geant4", "AdePT", "Celeritas", "G4HepEm"},
    "ACTS": {"Acts", "detray"},
    "GPU (traccc,vecmem,CUDA)": {"traccc", "vecmem", "CUDA", "APTypes"},
    "Triton client (gRPC,protobuf)": {"TritonClient", "TritonCommon", "gRPC"},
    "ML (onnxruntime,lwtnn)": {"onnxruntime", "lwtnn"},
    "FastJet": {"FastJet", "FastJetContrib"},
    "Qt/Coin3D": {"Qt5", "Coin3D", "SoQt", "OpenGL"},
    "MC generators": {
        "Pythia8",
        "Herwig3",
        "ThePEG",
        "Sherpa",
        "EvtGen",
        "Photospp",
        "Tauolapp",
        "Hijing",
        "Starlight",
        "Crmc",
        "EPOS4",
        "OpenLoops",
        "MadGraph",
        "Superchic",
        "SFGen",
        "Pepper",
        "Hto4l",
        "Prophecy4f",
        "Recola",
        "Apfel",
        "contur",
        "chaplin",
        "cln",
        "ginac",
        "ggvvamp",
        "qqvvamp",
        "nlox",
    },
    "HepMC3/HepPDT": {"hepmc3", "HepMC", "HepPDT"},
    "LHAPDF/Rivet/YODA": {"Lhapdf", "Rivet", "YODA"},
    "HDF5": {"HDF5", "HighFive"},
}


# Bare link names that come from externals.
BARE = [
    (re.compile(r"^(GaudiKernel|GaudiPluginService|Gaudi::.*)$"), "Gaudi"),
    (re.compile(r"^Acts::"), "Acts"),
    (re.compile(r"^Qt5::"), "Qt5"),
    (re.compile(r"^GL$"), "OpenGL"),
    (re.compile(r"^Boost::"), "Boost"),
    (re.compile(r"^nlohmann_json::"), "nlohmann_json"),
    (re.compile(r"^vecmem::"), "vecmem"),
    (re.compile(r"^traccc::"), "traccc"),
    (re.compile(r"^detray::"), "detray"),
    (re.compile(r"^chai::"), "chai"),
    (re.compile(r"^CrestApi::"), "CrestApi"),
    (re.compile(r"^TritonClient::"), "TritonClient"),
    (re.compile(r"^gRPC::"), "gRPC"),
    (re.compile(r"^bmpi3::"), "bmpi3"),
    (re.compile(r"^GTest::"), "GTest"),
]


def ext_from_item(item, fps_upper):
    out = set()
    for m in re.findall(r"@EXT:([^@]+)@", item):
        if m.startswith("CMAKE_") or m in ("extra_libs",):
            continue
        base = re.sub(
            r"_(HL_)?(LIBRARIES|LIBRARY|INCLUDE_DIRS|INCLUDE_DIR|"
            r"HepMC3\w*_LIBRARY)$",
            "",
            m,
        )
        out.add(fps_upper.get(base.upper(), base))
    if "@" not in item:
        for rx, name in BARE:
            if rx.search(item):
                out.add(name)
    return out


def build(pkgs, target_pkg):
    all_fp = {}
    for d in pkgs.values():
        for k in d["find_packages"]:
            all_fp[k.upper()] = k
    all_fp.update(
        {
            "TDAQ-COMMON": "tdaq-common",
            "TDAQ": "tdaq",
            "QT5": "Qt5",
            "GEANT4": "Geant4",
            "HEPMC3": "hepmc3",
            "OPENGL": "OpenGL",
        }
    )
    g = {}
    for p, d in pkgs.items():
        deps = collections.defaultdict(set)
        ext = set(k for k in d["find_packages"] if not NOT_EXTERNAL.search(k))
        tus = test_tus = gen = 0
        kinds = collections.Counter()
        for t in d["targets"]:
            kinds[t["kind"]] += 1
            items = t["links"] + t["private_links"] + t["includes"]
            for it in items:
                ext |= ext_from_item(it, all_fp)
                q = target_pkg.get(it)
                if q and q != p:
                    if t["kind"] in LIB_KINDS:
                        deps["lib"].add(q)
                    if t["kind"] in BUILD_KINDS:
                        deps["build"].add(q)
                    deps["test"].add(q)
            if t["kind"] == "test":
                test_tus += len(t["tus"])
            else:
                tus += len(t["tus"])
                gen += t["gen_tus"]
        g[p] = {
            "deps": sorted(deps["build"]),
            "deps_lib": sorted(deps["lib"]),
            "deps_test": sorted(deps["test"]),
            "externals": sorted(ext),
            "tus": tus,
            "test_tus": test_tus,
            "gen_tus": gen,
            "kinds": dict(kinds),
            "python": d["python"],
        }
    return g


def tarjan(nodes, edges):
    idx = {}
    low = {}
    on = set()
    st = []
    out = []
    counter = [0]
    sys.setrecursionlimit(100000)

    def sc(v):
        idx[v] = low[v] = counter[0]
        counter[0] += 1
        st.append(v)
        on.add(v)
        for w in edges.get(v, ()):
            if w not in nodes:
                continue
            if w not in idx:
                sc(w)
                low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], idx[w])
        if low[v] == idx[v]:
            comp = []
            while True:
                w = st.pop()
                on.discard(w)
                comp.append(w)
                if w == v:
                    break
            out.append(comp)

    for v in sorted(nodes):
        if v not in idx:
            sc(v)
    return out


def closure(g, roots, key="deps"):
    seen = set()
    todo = list(roots)
    while todo:
        p = todo.pop()
        if p in seen:
            continue
        seen.add(p)
        todo.extend(g[p][key])
    return seen


def group_of(ext):
    out = set()
    for gname, members in GROUPS.items():
        if ext & members:
            out.add(gname)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pkg")
    a = ap.parse_args()
    with open(os.path.join(WORK, "pkgs.json")) as f:
        pkgs = json.load(f)
    with open(os.path.join(WORK, "targets.json")) as f:
        target_pkg = json.load(f)
    g = build(pkgs, target_pkg)
    with open(os.path.join(WORK, "graph.json"), "w") as f:
        json.dump(g, f, indent=1, sort_keys=True)
    if a.pkg:
        d = g[a.pkg]
        print(json.dumps(d, indent=1))
        c = closure(g, [a.pkg])
        print(f"closure: {len(c)} packages, {sum(g[p]['tus'] for p in c)} TUs")
        return

    nodes = set(g)
    for key in ("deps_lib", "deps", "deps_test"):
        comps = [c for c in tarjan(nodes, {p: g[p][key] for p in g}) if len(c) > 1]
        print(
            f"package cycles via {key}: {len(comps)} SCCs, sizes "
            f"{sorted((len(c) for c in comps), reverse=True)[:10]}"
        )
        for c in sorted(comps, key=len, reverse=True)[:8]:
            print("   ", sorted(c)[:8], "..." if len(c) > 8 else "")

    # target level (non-test targets)
    tedges = collections.defaultdict(set)
    tkind = {}
    for p, d in pkgs.items():
        for t in d["targets"]:
            if t["kind"] == "test":
                continue
            tkind[t["name"]] = (t["kind"], t["interface"] or not t["tus"])
            for it in t["links"] + t["private_links"]:
                if it in target_pkg:
                    tedges[t["name"]].add(it)
    comps = [c for c in tarjan(set(tkind), tedges) if len(c) > 1]
    print(
        f"target-level cycles: {len(comps)}:",
        [
            sorted((n, tkind[n][0] + ("/iface" if tkind[n][1] else "")) for n in c)
            for c in comps
        ],
    )

    for level in (1, 2):

        def sub(p):
            return "/".join(p.split("/")[:level])

        for key in ("deps_lib", "deps"):
            se = collections.defaultdict(set)
            for p in g:
                for q in g[p][key]:
                    if sub(p) != sub(q):
                        se[sub(p)].add(sub(q))
            subs = {sub(p) for p in g}
            comps = [c for c in tarjan(subs, se) if len(c) > 1]
            print(
                f"subsystem level {level} via {key}: {len(subs)} subsystems, "
                f"SCC sizes {sorted((len(c) for c in comps), reverse=True)[:6]}"
            )
            if level == 1 and comps:
                big = max(comps, key=len)
                print("    largest:", sorted(big))
                print("    outside:", sorted(subs - set(big)))

    # externals
    ec = collections.Counter()
    gc = collections.Counter()
    for p, d in g.items():
        ec.update(d["externals"])
        gc.update(group_of(set(d["externals"])))
    print("packages per external:", ec.most_common(40))
    print("packages per external group (direct):", gc.most_common())


if __name__ == "__main__":
    main()
