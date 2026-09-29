"""Cross-package #includes that the CMake link graph does not declare.

ATLAS targets export only their own package directory as include path (see the
INTERFACE_INCLUDE_DIRECTORIES of the exported targets), so `#include "Pkg/X.h"` compiles only if
Pkg is in the target's (transitive) link closure -- or if another route puts it on the path.
This scans every compiled TU and every header of every package, maps `"Dir/..."` includes to the
package that owns `Dir/` (its public header directory), and compares with the link closure.

    python3 athena-notes/analysis/scripts/includes.py [--rescan]

Caches raw include lists in _work/includes.json (first run reads ~40k files from CVMFS).
"""

import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import depgraph  # noqa: E402
import graph  # noqa: E402
from scan import RELEASE, WORK  # noqa: E402

INC = re.compile(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]', re.M)
HDR = (".h", ".hh", ".hpp", ".icc", ".ixx", ".tcc", ".ipp")


def scan(pkgs, pfiles):
    out = {}
    src = os.path.join(RELEASE, "src")
    for p, d in pkgs.items():
        tus = set()
        for t in d["targets"]:
            for f in t["tus"]:
                tus.add(f)
        hdrs = {f for f in pfiles[p] if f.endswith(HDR)}
        rec = {}
        for f in sorted(tus | hdrs):
            try:
                with open(os.path.join(src, p, f), errors="replace") as fh:
                    rec[f] = sorted(set(INC.findall(fh.read())))
            except OSError:
                continue
        out[p] = rec
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rescan", action="store_true")
    ap.add_argument("--show", type=int, default=25)
    a = ap.parse_args()
    texts, files = depgraph.load()
    pfiles = depgraph.package_files(texts, files)
    with open(os.path.join(WORK, "pkgs.json")) as f:
        pkgs = json.load(f)
    with open(os.path.join(WORK, "graph.json")) as f:
        g = json.load(f)
    cache = os.path.join(WORK, "includes.json")
    if a.rescan or not os.path.exists(cache):
        inc = scan(pkgs, pfiles)
        with open(cache, "w") as f:
            json.dump(inc, f)
    else:
        with open(cache) as f:
            inc = json.load(f)

    # header dir -> packages
    owner = collections.defaultdict(set)
    for p, fl in pfiles.items():
        for f in fl:
            if "/" in f and f.endswith(HDR):
                owner[f.split("/")[0]].add(p)
    ambiguous = {k: v for k, v in owner.items() if len(v) > 1}
    # a dir named like the package wins
    own = {}
    for k, v in owner.items():
        named = [p for p in v if p.split("/")[-1] == k]
        if len(v) == 1:
            own[k] = next(iter(v))
        elif len(named) == 1:
            own[k] = named[0]
    skip_dirs = {
        "src",
        "test",
        "util",
        "Root",
        "python",
        "share",
        "data",
        "doc",
        "tests",
    }

    compiled = {p: {f for t in d["targets"] for f in t["tus"]} for p, d in pkgs.items()}
    stats = collections.Counter()
    undeclared = collections.defaultdict(lambda: collections.defaultdict(set))
    for p, rec in inc.items():
        clo = graph.closure(g, [p], "deps_test")
        for f, incs in rec.items():
            is_tu = f in compiled[p]
            for i in incs:
                top = i.split("/")[0]
                if "/" not in i or top in skip_dirs or top not in own:
                    continue
                q = own[top]
                if q == p:
                    continue
                stats["cross" + ("_tu" if is_tu else "_hdr")] += 1
                if q not in clo:
                    kind = (
                        "tu"
                        if is_tu
                        else (
                            "hdr_public"
                            if f.split("/")[0] == p.split("/")[-1]
                            else "hdr_other"
                        )
                    )
                    stats["undeclared_" + kind] += 1
                    undeclared[p][q].add(kind)
    print(
        "header dirs:",
        len(owner),
        "ambiguous:",
        len(ambiguous),
        "resolved ambiguous:",
        sum(1 for k in ambiguous if k in own),
    )
    print("cross-package include lines:", dict(stats))
    pk_tu = {p for p, qs in undeclared.items() if any("tu" in k for k in qs.values())}
    pairs_tu = sum(
        1 for p, qs in undeclared.items() for q, k in qs.items() if "tu" in k
    )
    pairs = sum(len(qs) for qs in undeclared.values())
    print(
        f"packages with undeclared includes (any file): {len(undeclared)}, pairs {pairs}"
    )
    print(f"  from compiled TUs: {len(pk_tu)} packages, {pairs_tu} pairs")
    # most common undeclared targets
    tgt = collections.Counter(
        q for qs in undeclared.values() for q, k in qs.items() if "tu" in k
    )
    print("most-included undeclared packages (from TUs):", tgt.most_common(15))
    shown = 0
    for p in sorted(pk_tu):
        qs = {q: sorted(k) for q, k in undeclared[p].items() if "tu" in k}
        print(f"   {p}: {qs}")
        shown += 1
        if shown >= a.show:
            break
    with open(os.path.join(WORK, "undeclared.json"), "w") as f:
        json.dump(
            {p: {q: sorted(k) for q, k in qs.items()} for p, qs in undeclared.items()},
            f,
            indent=1,
            sort_keys=True,
        )


if __name__ == "__main__":
    main()
