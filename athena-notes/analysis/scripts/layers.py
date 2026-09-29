"""Partition Athena into deliverable-driven layers and check closure and cost.

A layer is defined by what it should deliver: seed packages (regexes on the package path, or
"@Project" for an ATLAS project's package set), minus seeds whose dependency closure would drag
in a forbidden external or package (those are reported and left for a later layer), plus the
closure of the remaining seeds, plus an "absorb" pass that pulls in unassigned packages matching
the layer's absorb regex whose whole closure is already available (leaf tests, examples, small
tools). The last layer takes everything left over. By construction no package depends on a
later layer; the report re-checks that and also counts test dependencies on later layers.

    python3 athena-notes/analysis/scripts/layers.py [--sec-per-tu 8 15] [--cores 4]
    python3 athena-notes/analysis/scripts/layers.py --list core
    python3 athena-notes/analysis/scripts/layers.py --why Tracking/TrkEvent/TrkTrack
    python3 athena-notes/analysis/scripts/layers.py --dropped edm

Reads _work/graph.json (graph.py), _work/heavy.json (heavy.py), _work/libmb.json (stats.py),
_work/projects.json (projects.py). Writes _work/layers.json {package: layer}.
"""

import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import graph  # noqa: E402
from scan import WORK  # noqa: E402

HEAVY_TOP = {"Geant4", "Qt/Coin3D", "MC generators", "GPU (traccc,vecmem,CUDA)"}

LAYERS = [
    dict(
        name="core",
        desc="Gaudi/Athena framework, StoreGate, python configuration, AthenaMP, PerfMon, "
        "POOL/RNTuple I/O, IOVDb conditions access, ByteStream I/O, xAOD core + EventInfo. "
        "Deliverable: run athena.py jobs, write and run algorithms, read/write files.",
        seeds=[
            r"(Control|Database|AtlasTest|Tools)/",
            r"Event/(EventInfo|EventInfoMgt|EventInfoUtils|EventTPCnv|EventAthenaPool|"
            r"ByteStream|EventBookkeeper|EventContainers|EventPrimitives)",
            r"Event/xAOD/xAOD(Core|EventInfo|EventFormat|CnvInterfaces|Metadata|CutFlow)"
            r"(AthenaPool)?$",
        ],
        forbid_ext=HEAVY_TOP
        | {
            "GeoModel",
            "ACTS",
            "ML (onnxruntime,lwtnn)",
            "FastJet",
            "HDF5",
            "Triton client (gRPC,protobuf)",
        },
        forbid_pkg=r"Control/(AthCUDA|AthDevice|AthTriton|AthOnnx|AthenaExamples/AthExDevice)",
        absorb=None,
    ),
    dict(
        name="detdescr",
        desc="Identifiers/IdDict, GeoModel geometry of every subdetector, readout geometry, "
        "ACTS tracking geometry, magnetic field, cabling and detector conditions data. "
        "Deliverable: build and dump the ATLAS geometry, decode identifiers.",
        seeds=[
            r"DetectorDescription/",
            r"AtlasGeometryCommon/",
            r"MagneticField/",
            r".*GeoModel",
            r".*(Identifier|IdHelpers|IdCnv|DetDescr|ReadoutGeometry|"
            r"Cabling|TrackingGeometry)$",
            r".*/\w+(ConditionsData|CondData)$",
            r"Tracking/Acts/ActsGeometry",
            r"MuonSpectrometer/MuonCablings/",
            r".*[Cc]abling",
        ],
        forbid_ext=HEAVY_TOP
        | {"ML (onnxruntime,lwtnn)", "FastJet", "Triton client (gRPC,protobuf)"},
        forbid_pkg=r"TestBeam/|Simulation/(?!HitManagement$)",
        absorb=r"(DetectorDescription|AtlasGeometryCommon|MagneticField)/|.*GeoModel|.*DetDescr",
    ),
    dict(
        name="edm",
        desc="xAOD, trigger and generic event data model (Event/, Trigger/TrigEvent, "
        "Tracking/TrkEvent, GeneratorObjects) with T/P and AthenaPool converters and "
        "dictionaries. Deliverable: read and write AOD/DAOD (xAOD) in Athena and PyROOT.",
        seeds=[
            r"Event/",
            r"Tracking/TrkEvent/",
            r"Trigger/TrigEvent/",
            r"Generators/GeneratorObjects",
            r"Reconstruction/\w*(Event|EventTPCnv|"
            r"AthenaPool|TPCnv)$",
            r"PhysicsAnalysis/.*(Event|EventTPCnv|AthenaPool)$",
        ],
        forbid_ext=HEAVY_TOP
        | {"ML (onnxruntime,lwtnn)", "Triton client (gRPC,protobuf)"},
        forbid_pkg=r"PhysicsAnalysis/DerivationFramework",
        # EDM means data classes: a package with Gaudi components that are not converters
        # (algorithms, tools, services) belongs to a later layer.
        forbid_components=True,
        absorb=r"Event/|Trigger/TrigEvent/",
    ),
    dict(
        name="edm-det",
        desc="Detector-level event data: raw data objects, prep raw data, RIO_OnTrack, sim "
        "hits for ID/ITk, calorimeters, muons, forward detectors and HGTD, with their "
        "T/P, AthenaPool and bytestream converters. Deliverable: read and write "
        "RDO/ESD/HITS.",
        seeds=[
            r".*/\w*(Event|EventTPCnv|EventAthenaPool|AthenaPool|TPCnv|RawData|RawEvent|"
            r"PrepRawData|RIO_OnTrack|SimEvent|EventCnv|SimData|RDO)$"
        ],
        forbid_ext=HEAVY_TOP
        | {"ML (onnxruntime,lwtnn)", "Triton client (gRPC,protobuf)"},
        forbid_pkg=r"PhysicsAnalysis/DerivationFramework",
        forbid_components=True,
        absorb=r".*(Event|AthenaPool|TPCnv|RawData)$",
    ),
    dict(
        name="analysis",
        desc="The AthAnalysis package set built in Athena mode: CP tools, analysis algorithms, "
        "trigger decision tool, systematics handling. Deliverable: AthAnalysis-style "
        "analysis of DAOD_PHYS/PHYSLITE inside Athena.",
        seeds=["@AthAnalysis"],
        forbid_ext=HEAVY_TOP,
        forbid_pkg=None,
        absorb=r"PhysicsAnalysis/(AnalysisCommon|ElectronPhotonID|MuonID|JetMissingEtID|"
        r"TauID|JetTagging|Algorithms|Interfaces|TrackingID)",
    ),
    dict(
        name="sim",
        desc="Generator interfaces (AthGeneration), Geant4 full simulation, ISF/FastCaloSim, "
        "sensitive detectors of all subdetectors (AthSimulation). Deliverable: Sim_tf.py "
        "(EVNT -> HITS), Gen_tf.py for generators available on conda-forge.",
        seeds=[
            "@AthSimulation",
            "@AthGeneration",
            r"Simulation/",
            r"Generators/",
            r".*(G4_SD|G4Sim|G4Utilities|SimUtils)$",
        ],
        forbid_ext={"Qt/Coin3D", "GPU (traccc,vecmem,CUDA)"},
        forbid_pkg=r"Trigger/(?!TrigT1/TrigT1Interfaces|TrigEvent|TrigConfiguration)",
        absorb=r"Simulation/|Generators/",
    ),
    dict(
        name="reco-tracking",
        desc="Inner-detector and ITk data preparation and tracking (legacy Trk, InDet, ACTS "
        "CPU), HGTD, vertexing, ID digitization. Deliverable: RDO -> tracks/vertices for "
        "ID/ITk; the tracking piece of Reco_tf.py.",
        seeds=[r"InnerDetector/", r"Tracking/", r"HighGranularityTimingDetector/"],
        forbid_ext={"Qt/Coin3D", "GPU (traccc,vecmem,CUDA)"},
        forbid_pkg=r"Trigger/(TrigHypothesis|TrigMonitoring|TrigValidation|TriggerCommon|"
        r"TrigAlgorithms|EFTracking|TrigAccel)|HLT/|DataQuality/|"
        r"PhysicsAnalysis/DerivationFramework|MuonSpectrometer/|"
        r"Reconstruction/(egamma|Jet|tau|MET|MuonIdentification|PFlow|RecExample|"
        r"RecJobTransforms|DiTau|PanTau|eflow|HeavyIon)",
        absorb=r"InnerDetector/|Tracking/|HighGranularityTimingDetector/",
    ),
    dict(
        name="reco",
        desc="Digitization/overlay and offline reconstruction: tracking (InDet/ITk, Trk, ACTS), "
        "calorimetry, muons, egamma, jets/MET/tau/PFlow/b-tagging, RecJobTransforms. "
        "Deliverable: Digi_tf.py and Reco_tf.py (HITS/RAW -> AOD) without trigger.",
        seeds=[
            r"Reconstruction/",
            r"Tracking/",
            r"InnerDetector/",
            r"MuonSpectrometer/",
            r"Calorimeter/",
            r"LArCalorimeter/",
            r"TileCalorimeter/",
            r"HighGranularityTimingDetector/",
            r"ForwardDetectors/",
            r"LumiBlock/",
            r".*Digitization",
        ],
        forbid_ext={"Qt/Coin3D", "GPU (traccc,vecmem,CUDA)"},
        # Reconstruction needs a few trigger packages (ViewAlgs for IDC caches, L1 hardware
        # emulation for RPC/L1Calo decoding); the HLT proper, the menu and monitoring are
        # forbidden.
        forbid_pkg=r"Trigger/(TrigHypothesis|TrigMonitoring|TrigValidation|TriggerCommon|"
        r"TrigAlgorithms|EFTracking|TrigAccel)|HLT/|DataQuality/|"
        r"PhysicsAnalysis/DerivationFramework",
        absorb=r"Reconstruction/|Tracking/|InnerDetector/|MuonSpectrometer/|Calorimeter/|"
        r"LArCalorimeter/|TileCalorimeter/|HighGranularityTimingDetector/|"
        r"ForwardDetectors/",
    ),
    dict(
        name="trigger",
        desc="Trigger: L1 simulation, HLT steering/algorithms/hypos, menu, EF tracking, "
        "trigger monitoring. Deliverable: trigger in RAW->AOD reconstruction and "
        "RDO->RDO_TRIG.",
        seeds=[r"Trigger/", r"HLT/"],
        forbid_ext={"Qt/Coin3D"},
        forbid_pkg=r"DataQuality/|PhysicsAnalysis/DerivationFramework",
        absorb=r"Trigger/|HLT/",
    ),
    dict(
        name="rest",
        desc="Derivation framework (Derivation_tf.py), data quality, VP1 event display, "
        "validation, test beam, GPU/Triton clients and everything left.",
        seeds=[r".*"],
        forbid_ext=set(),
        forbid_pkg=None,
        absorb=None,
    ),
]


def load_projects():
    fn = os.path.join(WORK, "projects.json")
    if os.path.exists(fn):
        with open(fn) as f:
            return {k: set(v) for k, v in json.load(f).items()}
    return {}


def seed_set(g, spec, projects):
    out = set()
    for s in spec:
        if s.startswith("@"):
            out |= projects.get(s[1:], set()) & set(g)
        else:
            rx = re.compile("^(" + s + ")")
            out |= {p for p in g if rx.match(p)}
    return out


# Tests, examples and validation/monitoring packages are never seeds: they are what a layer
# drags in "by accident" (MuonGeoModelTest links the xAOD EDM, AthViews the calorimeter...).
# They join a layer through its absorb pass once everything they need is there.
NOT_SEED = re.compile(
    r".*(Test|Tests|TestR4|Example|Examples|Validation|Monitoring|"
    r"Dumper|Dump)$"
)
ALLOW_COMPONENTS = re.compile(
    r".*/(TrkEventCnvTools|TrigNavigation|TrigConfBase|"
    r"TrigSerialize\w*|InDetMeasurementUtilities)$"
)


def build_layers(g, layers=LAYERS):
    projects = load_projects()
    assigned = {}
    dropped = {}
    for L in layers:
        name = L["name"]
        seed = {
            p
            for p in seed_set(g, L["seeds"], projects)
            if p not in assigned
            and (name == layers[-1]["name"] or not NOT_SEED.match(p))
        }
        frx = re.compile("^(" + L["forbid_pkg"] + ")") if L["forbid_pkg"] else None

        def bad(p):
            if p in assigned:
                return False
            if frx and frx.match(p):
                return True
            if (
                L.get("forbid_components")
                and "component" in g[p]["kinds"]
                and not re.search(r"(AthenaPool|Cnv|TPCnv|Conv)$", p)
                and not ALLOW_COMPONENTS.match(p)
            ):
                return True
            return bool(graph.group_of(set(g[p]["externals"])) & L["forbid_ext"])

        keep = set()
        drop = {}
        for p in seed:
            offenders = [q for q in graph.closure(g, [p]) if bad(q)]
            if offenders:
                drop[p] = sorted(offenders)
            else:
                keep.add(p)
        dropped[name] = drop
        for p in graph.closure(g, keep):
            assigned.setdefault(p, name)
        if L["absorb"]:
            rx = re.compile("^(" + L["absorb"] + ")")
            changed = True
            while changed:
                changed = False
                for p in g:
                    if p in assigned or not rx.match(p) or bad(p):
                        continue
                    if all(q in assigned or q == p for q in graph.closure(g, [p])):
                        assigned[p] = name
                        changed = True
    for p in g:
        assigned.setdefault(p, layers[-1]["name"])
    return assigned, dropped


def why(g, assigned, target, layers=LAYERS):
    """Shortest dependency path from a seed of target's layer to target."""
    layer = assigned[target]
    projects = load_projects()
    L = next(x for x in layers if x["name"] == layer)
    seed = {p for p in seed_set(g, L["seeds"], projects) if assigned[p] == layer}
    prev = {p: None for p in seed}
    todo = collections.deque(sorted(seed))
    while todo:
        p = todo.popleft()
        if p == target:
            path = []
            while p:
                path.append(p)
                p = prev[p]
            return path
        for q in g[p]["deps"]:
            if q not in prev:
                prev[q] = p
                todo.append(q)
    return None


def layer_stats(g, ps, heavy):
    tu = sum(g[p]["tus"] for p in ps)
    gen = sum(g[p]["gen_tus"] for p in ps)
    tt = sum(g[p]["test_tus"] for p in ps)
    ext = set()
    for p in ps:
        ext |= set(g[p]["externals"])
    hv = collections.Counter()
    hn = hs = 0
    for p in ps:
        h = heavy.get(p)
        if h:
            hv.update(h["reach"])
            hn += h["tus"]
            hs += h["hdrs_mean"] * h["tus"]
    return dict(
        pkgs=len(ps),
        tu=tu,
        gen=gen,
        tt=tt,
        ext=ext,
        pct={k: (100 * v / hn if hn else 0) for k, v in hv.items()},
        hdr=hs / hn if hn else 0,
        libmb=sum(g[p].get("libMB", 0) for p in ps),
    )


def report(g, assigned, layers, secs, cores, heavy):
    order = [L["name"] for L in layers]
    rank = {n: i for i, n in enumerate(order)}
    by = collections.defaultdict(list)
    for p, layer in assigned.items():
        by[layer].append(p)
    viol = [
        (p, q) for p in g for q in g[p]["deps"] if rank[assigned[q]] > rank[assigned[p]]
    ]
    tviol = collections.defaultdict(set)
    for p in g:
        for q in g[p]["deps_test"]:
            if rank[assigned[q]] > rank[assigned[p]]:
                tviol[assigned[p]].add(p)
    print(f"build-dependency violations (package needs a later layer): {len(viol)}")
    print(
        f"| layer | pkgs | TU | gen TU | test TU | CPU-h @{secs[0]:g}s | CPU-h @{secs[-1]:g}s "
        f"| wall h on {cores} cores @{secs[-1]:g}s | wall h on 2 cores @{secs[-1]:g}s | Eigen % | ACTS % | G4 % | hdrs/TU "
        f"| lib MB | heavy externals (besides Gaudi/ROOT/Boost) | pkgs whose tests need later layers |"
    )
    print("|" + "---|" * 16)
    tot = collections.Counter()
    for n in order:
        s = layer_stats(g, by[n], heavy)
        build = s["tu"] + s["gen"]
        cpu = [build * x / 3600 for x in secs]
        print(
            f"| {n} | {s['pkgs']} | {s['tu']} | {s['gen']} | {s['tt']} | {cpu[0]:.1f} | "
            f"{cpu[-1]:.1f} | {cpu[-1] / cores:.1f} | {cpu[-1] / 2:.1f} | "
            f"{s['pct'].get('Eigen', 0):.0f} | "
            f"{s['pct'].get('Acts', 0):.0f} | {s['pct'].get('Geant4', 0):.0f} | "
            f"{s['hdr']:.0f} | {s['libmb']:.0f} | "
            f"{', '.join(sorted(graph.group_of(s['ext']) - {'Gaudi'}))} | "
            f"{len(tviol.get(n, ()))} |"
        )
        tot.update({k: s[k] for k in ("pkgs", "tu", "gen", "tt")})
    print(f"| total | {tot['pkgs']} | {tot['tu']} | {tot['gen']} | {tot['tt']} |")
    print()
    print("layer-level dependencies (direct; build / tests only):")
    for n in order:
        dep = collections.Counter(
            assigned[q] for p in by[n] for q in g[p]["deps"] if assigned[q] != n
        )
        tdep = collections.Counter(
            assigned[q]
            for p in by[n]
            for q in g[p]["deps_test"]
            if assigned[q] != n and assigned[q] not in dep
        )
        print(
            f"  {n}: "
            + ", ".join(
                f"{k} ({v} edges)"
                for k, v in sorted(dep.items(), key=lambda x: rank[x[0]])
            )
            + (("; tests only: " + ", ".join(sorted(tdep))) if tdep else "")
        )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sec-per-tu", type=float, nargs="+", default=[8, 15])
    ap.add_argument("--cores", type=int, default=4)
    ap.add_argument("--list")
    ap.add_argument("--why", nargs="+")
    ap.add_argument("--dropped")
    a = ap.parse_args()
    with open(os.path.join(WORK, "graph.json")) as f:
        g = json.load(f)
    heavy = {}
    hf = os.path.join(WORK, "heavy.json")
    if os.path.exists(hf):
        with open(hf) as f:
            heavy = json.load(f)
    lb = os.path.join(WORK, "libmb.json")
    if os.path.exists(lb):
        with open(lb) as f:
            for p, v in json.load(f).items():
                if p in g:
                    g[p]["libMB"] = v
    assigned, dropped = build_layers(g)
    with open(os.path.join(WORK, "layers.json"), "w") as f:
        json.dump(assigned, f, indent=1, sort_keys=True)
    if a.why:
        for t in a.why:
            print(
                t,
                "[" + assigned[t] + "]:",
                " <- ".join(reversed(why(g, assigned, t) or [])),
            )
        return
    if a.dropped:
        for p, offs in sorted(dropped[a.dropped].items()):
            print(
                f"   {p} [-> {assigned[p]}]: {offs[:4]}{' ...' if len(offs) > 4 else ''}"
            )
        return
    if a.list:
        for p in sorted(p for p in g if assigned[p] == a.list):
            print(f"   {p} {g[p]['tus'] + g[p]['gen_tus']}")
        return
    for L in LAYERS:
        print(
            f"- {L['name']}: {L['desc']} (seeds dropped for forbidden deps: "
            f"{len(dropped[L['name']])})"
        )
    print()
    report(g, assigned, LAYERS, a.sec_per_tu, a.cores, heavy)


if __name__ == "__main__":
    main()
