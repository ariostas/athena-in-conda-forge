"""The python packages and component types an Athena configuration uses.

    cvmfs-athena.sh python cfgdeps.py <module> <out.json> [job arguments ...]

Runs `python -m <module> --config-only=cfgdeps.pkl` in-process, then writes to <out.json> the
top-level python packages imported from the release's install areas and the C++ types of every
component in the stored configuration (algorithms, services, tools, recursively through tool
handles). Mapping those to packages and layers: the release's <project>.components files give
the library of each component, _work/targets.json the package of each library.
"""

import json
import pickle
import runpy
import sys

mod, out = sys.argv[1], sys.argv[2]
sys.argv = [mod, "--config-only=cfgdeps.pkl"] + sys.argv[3:]
try:
    runpy.run_module(mod, run_name="__main__")
except SystemExit:
    pass
mods = sorted(
    {
        m.split(".")[0]
        for m, v in sys.modules.items()
        if "/InstallArea/" in (getattr(v, "__file__", None) or "")
    }
)
with open("cfgdeps.pkl", "rb") as f:
    acc = pickle.load(f)

types = set()
seen = set()


def walk(c):
    if isinstance(c, (list, tuple)):
        for x in c:
            walk(x)
    elif isinstance(c, dict):
        for x in c.values():
            walk(x)
    elif getattr(c, "__cpp_type__", None):
        key = (c.__cpp_type__, getattr(c, "name", ""))
        if key in seen:
            return
        seen.add(key)
        types.add(c.__cpp_type__)
        for p in getattr(c, "_properties", {}).values():
            walk(p)


for attr in (
    "_allSequences",
    "_algorithms",
    "_conditionsAlgs",
    "_services",
    "_publicTools",
    "_privateTools",
    "_auditors",
):
    walk(getattr(acc, attr, None))
with open(out, "w") as f:
    json.dump({"modules": mods, "types": sorted(types)}, f, indent=1)
print(len(mods), "modules,", len(types), "component types")
