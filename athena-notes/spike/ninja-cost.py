"""Per-step build cost from a ninja build directory's .ninja_log.

usage: ninja-cost.py <build dir> [...]
Prints, per kind of output, the count and the summed duration (ninja records wall time
per job; with fewer jobs than cores that is close to CPU time).
"""

import collections
import sys


def kind(out):
    if out.endswith(".o"):
        if "/test/" in out or "_test.dir" in out:
            return "compile test"
        if "Dict" in out or "dict" in out.lower() and "Dict" in out:
            return "compile dict"
        return "compile"
    if out.endswith((".so", ".exe")) or "/bin/" in out:
        return "link"
    if "Dict" in out and out.endswith((".cxx", ".cpp")):
        return "genreflex"
    if out.endswith((".confdb", ".confdb2", "Conf.py")) or "genConf" in out:
        return "genconf"
    if out.endswith("_clid.db"):
        return "genCLIDDB"
    if out.endswith(".components"):
        return "listcomponents"
    return "other"


for bld in sys.argv[1:]:
    seen = {}
    with open(f"{bld}/.ninja_log") as f:
        for line in f:
            if line.startswith("#"):
                continue
            start, end, _, out, _ = line.rstrip("\n").split("\t")
            seen[out] = int(end) - int(start)  # last build of each output wins
    tot = collections.defaultdict(lambda: [0, 0])
    for out, ms in seen.items():
        k = kind(out)
        tot[k][0] += 1
        tot[k][1] += ms
    print(bld)
    for k, (n, ms) in sorted(tot.items(), key=lambda x: -x[1][1]):
        print(f"  {k:15s} {n:5d} {ms / 1000:8.1f} s  {ms / 1000 / n:6.2f} s each")
    print(
        f"  {'total':15s} {sum(v[0] for v in tot.values()):5d} "
        f"{sum(v[1] for v in tot.values()) / 1000:8.1f} s"
    )
