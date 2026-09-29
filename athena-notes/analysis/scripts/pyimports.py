"""Python import graph between Athena packages (from the release's packages.py.dot) versus the
proposed layers: how many imports point from a layer to a later one (runtime-only dependencies
that CMake does not see).

    python3 athena-notes/analysis/scripts/pyimports.py [--show core]

Reads _work/packages.py.dot (copied from the install area) and _work/layers.json.
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--show")
    a = ap.parse_args()
    with open(os.path.join(WORK, "layers.json")) as f:
        L = json.load(f)
    short = collections.defaultdict(list)
    for p in L:
        short[p.split("/")[-1]].append(p)
    edges = set()
    unknown = collections.Counter()
    with open(os.path.join(WORK, "packages.py.dot")) as f:
        for m in re.finditer(
            r"^\s*(\S+)\s*->\s*(\S+)\s*\[label=(\w+)\]", f.read(), re.M
        ):
            s, t, lab = m.groups()
            if s not in short or t not in short:
                unknown[s if s not in short else t] += 1
                continue
            edges.add((short[s][0], short[t][0], lab))
    labels = collections.Counter(lab for _, _, lab in edges)
    print(
        f"python edges between packages: {len(edges)} {dict(labels)}; "
        f"unresolved names: {len(unknown)} {unknown.most_common(5)}"
    )
    nodes = {s for s, _, _ in edges} | {t for _, t, _ in edges}
    adj = collections.defaultdict(set)
    for s, t, _ in edges:
        adj[s].add(t)
    comps = sorted(
        (c for c in graph.tarjan(nodes, adj) if len(c) > 1), key=len, reverse=True
    )
    print(f"python-import SCCs: {[len(c) for c in comps][:10]}")
    order = [
        "core",
        "detdescr",
        "edm",
        "edm-det",
        "analysis",
        "sim",
        "reco-tracking",
        "reco",
        "trigger",
        "rest",
    ]
    rank = {n: i for i, n in enumerate(order)}
    up = collections.Counter()
    upk = collections.defaultdict(collections.Counter)
    for s, t, _ in edges:
        if rank[L[t]] > rank[L[s]]:
            up[L[s]] += 1
            upk[L[s]][t] += 1
    tot = collections.Counter(L[s] for s, _, _ in edges)
    for n in order:
        print(
            f"  {n}: {tot[n]} import edges, {up[n]} to later layers; top targets "
            f"{[x.split('/')[-1] for x, _ in upk[n].most_common(6)]}"
        )
    if a.show:
        for s, t, lab in sorted(edges):
            if L[s] == a.show and rank[L[t]] > rank[L[s]]:
                print(f"   {s} -> {t} [{L[t]}]")


if __name__ == "__main__":
    main()
