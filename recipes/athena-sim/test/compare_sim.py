"""Compare a dump of a HITS file (PyDumper, as pool_rw.py writes it) with a summary of the dump of
ATLAS's release for the same job.

    python compare_sim.py summarize <dump>              (prints the summary, as JSON)
    python compare_sim.py check <dump> <summary.json>

Geant4 does not give the same showers here as in ATLAS's release (see the repository README's
entry): the check is that the input to Geant4 is identical (the generator-level truth record,
after the beam spot smearing: its vertices, by hash, event by event) and that the hits of every
detector are there in the same amounts (each collection's hits summed over the events, within
20% for the collections with at least 1,000 of them, and present for those with at least 10).
"""

import hashlib
import json
import re
import sys

HEADER = re.compile(r"^-+\[(.+)\]-+$")


def summarize(path):
    events = []
    coll = None
    for line in open(path):
        line = line.rstrip("\n")
        if line.startswith("==> evt"):
            events.append({"counts": {}, "generator": hashlib.sha256()})
            coll = None
            continue
        m = HEADER.match(line.strip())
        if m:
            coll = m.group(1)
            events[-1]["counts"][coll] = 0
            gen_vertex = False
            continue
        if coll is None or not events:
            continue
        events[-1]["counts"][coll] += 1
        if coll == "McEventCollection/TruthEvent":
            f = line.split()
            # generator vertices have barcodes above -200000 (Geant4's start at -200001), each
            # followed by its (incoming)(outgoing) line
            if f and f[0] in ("v", "v0"):
                gen_vertex = int(f[2]) > -200000
                if gen_vertex:
                    events[-1]["generator"].update(line.encode() + b"\n")
            elif f and f[0] == "(" and gen_vertex:
                events[-1]["generator"].update(line.encode() + b"\n")
            else:
                gen_vertex = False
    totals = {}
    for e in events:
        for c, n in e["counts"].items():
            totals[c] = totals.get(c, 0) + n
    return {
        "events": len(events),
        "generator": [e["generator"].hexdigest() for e in events],
        "totals": totals,
    }


def check(path, ref_path):
    ours = summarize(path)
    ref = json.load(open(ref_path))
    bad = []
    if ours["events"] != ref["events"]:
        bad.append(f"{ours['events']} events, ATLAS's release has {ref['events']}")
    for i, (a, b) in enumerate(zip(ours["generator"], ref["generator"])):
        if a != b:
            bad.append(f"event {i}: the generator-level truth record differs")
    for c, n in sorted(ref["totals"].items()):
        mine = ours["totals"].get(c, 0)
        status = "ok"
        if n >= 1000 and abs(mine / n - 1) > 0.2:
            status = "DIFFERS"
        elif n >= 10 and mine == 0:
            status = "MISSING"
        print(f"{c:60s} {mine:8d} {n:8d}  {status}")
        if status != "ok":
            bad.append(f"{c}: {mine} lines, ATLAS's release {n}")
    for b in bad:
        print("FAILED:", b)
    return not bad


if __name__ == "__main__":
    if sys.argv[1] == "summarize":
        json.dump(summarize(sys.argv[2]), sys.stdout, indent=1, sort_keys=True)
        print()
    elif not check(sys.argv[2], sys.argv[3]):
        sys.exit(1)
