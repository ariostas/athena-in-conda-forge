"""Map what an Athena configuration uses (cfgdeps.py output) to packages and layers.

    python3 athena-notes/analysis/scripts/cfgmap.py <cfgdeps.json> [--all]

Python modules map to the package that installs them (the package directory's name, as
atlas_install_python_modules does it), component types to the package of the library that
provides them (the release's Athena.components on CVMFS, then _work/targets.json). Prints the
packages outside the core layer (all of them with --all) with their layer, and the modules and
types that map to no Athena package (Gaudi's, for example).
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scan import WORK  # noqa: E402

COMPONENTS = (
    "/cvmfs/atlas.cern.ch/repo/sw/software/25.0/Athena/25.0.73/InstallArea/"
    "aarch64-el9-gcc15-opt/lib/Athena.components"
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("deps")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    with open(args.deps) as f:
        deps = json.load(f)
    with open(os.path.join(WORK, "graph.json")) as f:
        g = json.load(f)
    with open(os.path.join(WORK, "layers.json")) as f:
        layers = json.load(f)
    with open(os.path.join(WORK, "targets.json")) as f:
        targets = json.load(f)
    by_name = {}
    for p in g:
        by_name.setdefault(p.rsplit("/", 1)[-1], p)
    lib_of = {}
    with open(COMPONENTS) as f:
        for line in f:
            # v2::libName.so:Component
            lib, _, comp = line.strip().split("::", 1)[-1].partition(":")
            lib_of[comp] = lib.removeprefix("lib").removesuffix(".so")

    found = {}
    unmapped = []
    for m in deps["modules"]:
        if m in by_name:
            found.setdefault(by_name[m], set()).add(f"python {m}")
        else:
            unmapped.append(f"python {m}")
    for t in deps["types"]:
        lib = lib_of.get(t)
        pkg = targets.get(lib) if lib else None
        if pkg:
            found.setdefault(pkg, set()).add(t)
        else:
            unmapped.append(t)
    for p in sorted(found, key=lambda p: (layers.get(p, "?"), p)):
        if args.all or layers.get(p) != "core":
            print(f"{layers.get(p, '?'):14} {p}: {', '.join(sorted(found[p]))}")
    print("unmapped:", ", ".join(unmapped))


if __name__ == "__main__":
    main()
