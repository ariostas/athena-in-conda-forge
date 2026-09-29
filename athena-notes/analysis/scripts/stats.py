"""Size of Athena: packages, targets, translation units and installed libraries per subsystem.

    python3 athena-notes/analysis/scripts/stats.py [--level 1|2] [--md]

Reads _work/pkgs.json (depgraph.py), _work/graph.json (graph.py) and _work/lib_ls.txt
(`find lib -maxdepth 1 -printf '%s %y %P\\n'` of the install area).
"""

import argparse
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scan import WORK  # noqa: E402


def lib_sizes():
    sizes = {}
    with open(os.path.join(WORK, "lib_ls.txt")) as f:
        for ln in f:
            parts = ln.split()
            if len(parts) == 3 and parts[1] == "f":
                sizes[parts[2]] = int(parts[0])
    return sizes


def package_lib_bytes(pkgs, sizes):
    out = {}
    for p, d in pkgs.items():
        b = 0
        for t in d["targets"]:
            if t["kind"] == "test":
                continue
            for fn in (
                f"lib{t['name']}.so",
                f"lib{t['name']}_rdict.pcm",
                f"{t['name']}_rdict.pcm",
                f"lib{t['name']}.pcm",
            ):
                b += sizes.get(fn, 0)
        out[p] = b
    return out


def classify(d):
    """compiled / python-only / data-only(other)"""
    compiled = any(
        t["tus"] or t["gen_tus"] for t in d["targets"] if t["kind"] != "test"
    )
    if compiled:
        return "compiled"
    if any(
        t["kind"] in ("library", "tpcnv")
        and t["interface"]
        or (t["kind"] == "library" and not t["tus"])
        for t in d["targets"]
    ):
        return "header-only"
    if d["python"] or d["scripts"] or d["joboptions"]:
        return "python/scripts only"
    return "other (tests/data only)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--level", type=int, default=1)
    ap.add_argument("--md", action="store_true")
    a = ap.parse_args()
    with open(os.path.join(WORK, "pkgs.json")) as f:
        pkgs = json.load(f)
    sizes = lib_sizes()
    plb = package_lib_bytes(pkgs, sizes)
    with open(os.path.join(WORK, "libmb.json"), "w") as f:
        json.dump({p: b / 1e6 for p, b in plb.items()}, f, indent=0, sort_keys=True)
    rows = collections.defaultdict(lambda: collections.Counter())
    tot = collections.Counter()
    cls = collections.Counter()
    for p, d in pkgs.items():
        s = "/".join(p.split("/")[: a.level])
        r = rows[s]
        r["packages"] += 1
        c = classify(d)
        cls[c] += 1
        r["cls:" + c] += 1
        for t in d["targets"]:
            k = t["kind"]
            if k == "test" and t["script"]:
                r["test(script)"] += 1
                continue
            r[k] += 1
            if k == "test":
                r["tu_test"] += len(t["tus"])
            elif k == "executable":
                r["tu_exe"] += len(t["tus"])
            elif k == "component":
                r["tu_comp"] += len(t["tus"])
            else:
                r["tu_lib"] += len(t["tus"])
            r["tu_gen"] += t["gen_tus"]
        r["libMB"] += plb[p] / 1e6
        r["cxx_files"] += d["all_cxx"]
    cols = [
        "packages",
        "library",
        "component",
        "dictionary",
        "poolcnv",
        "tpcnv",
        "executable",
        "test",
        "test(script)",
        "tu_lib",
        "tu_comp",
        "tu_exe",
        "tu_gen",
        "tu_test",
        "cxx_files",
        "libMB",
    ]
    for r in rows.values():
        tot.update(r)
    hdr = ["subsystem"] + cols + ["TU(build)"]
    if a.md:
        print("| " + " | ".join(hdr) + " |")
        print("|" + "---|" * len(hdr))
    else:
        print(" ".join(f"{h:>10}" for h in hdr))
    for s in sorted(rows, key=lambda s: -(rows[s]["tu_lib"] + rows[s]["tu_comp"])) + [
        "TOTAL"
    ]:
        r = tot if s == "TOTAL" else rows[s]
        build = r["tu_lib"] + r["tu_comp"] + r["tu_exe"] + r["tu_gen"]
        vals = [s] + [f"{r[c]:.0f}" for c in cols] + [str(build)]
        if a.md:
            print("| " + " | ".join(vals) + " |")
        else:
            print(" ".join(f"{v:>10}" for v in vals))
    print("package classes:", dict(cls))
    print(
        f"lib/ total {sum(sizes.values()) / 1e9:.2f} GB, .so {sum(v for k, v in sizes.items() if k.endswith('.so')) / 1e9:.2f} GB, "
        f"attributed to packages {sum(plb.values()) / 1e9:.2f} GB"
    )


if __name__ == "__main__":
    main()
