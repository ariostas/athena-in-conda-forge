"""Dump the trees and histograms of ROOT files as text, for comparisons.

    python dump_ntuple.py <dump.txt> <file.root> ...

The entries of a tree with an eventNumber branch are sorted by run and event number: a
multi-threaded job writes events in no fixed order.
"""

import sys

import numpy as np
import uproot


def dump_tree(t, path, out):
    names = sorted(t.keys())
    out.append(f"TTree {path}: {t.num_entries} entries, {len(names)} branches")
    arrays = t.arrays(names, library="ak")
    order = slice(None)
    if "eventNumber" in names:
        keys = [np.asarray(arrays["eventNumber"])]
        if "runNumber" in names:
            keys.append(np.asarray(arrays["runNumber"]))
        order = np.lexsort(keys)
    for name in names:
        out.append(f"  {name} ({t[name].typename})")
        for i, v in enumerate(arrays[name][order].to_list()):
            out.append(f"    {i} {v!r}")


def dump_hist(h, path, out):
    out.append(f"{h.classname} {path}")
    for axis in h.axes:
        labels = axis.labels()
        out.append(f"  axis {list(axis.edges(flow=False)) if labels is None else labels}")
    out.append(f"  values {h.values(flow=True).tolist()!r}")
    out.append(f"  variances {h.variances(flow=True).tolist()!r}")


def walk(d, path, out):
    for name, cls in sorted(d.classnames(recursive=False, cycle=False).items()):
        p = f"{path}/{name}"
        if cls == "TDirectory":
            walk(d[name], p, out)
        elif cls == "TTree":
            dump_tree(d[name], p, out)
        elif cls.startswith("TH"):
            dump_hist(d[name], p, out)
        else:
            out.append(f"{cls} {p}")


out = []
for fn in sys.argv[2:]:
    out.append(f"file {fn.rsplit('/', 1)[-1]}")
    walk(uproot.open(fn), "", out)
with open(sys.argv[1], "w") as f:
    f.write("\n".join(out) + "\n")
