"""Evaluate every Athena package's CMakeLists.txt into targets, sources and link edges.

    python3 athena-notes/analysis/scripts/depgraph.py

Reads _work/cmakelists.json and _work/srcfiles.txt (from scan.py) and writes
_work/pkgs.json:

    {package: {"subsystem", "targets": [{name, kind, sources, tus, gen_tus, links,
               private_links, includes}], "find_packages": {...}, "python", "scripts",
               "wrapper_calls"}}

plus _work/targets.json {target: package}. "tus" are the C/C++/CUDA/Fortran files the
target compiles (globs expanded against the real source tree); "gen_tus" counts generated
translation units (1 per reflex dictionary, 1 per pool/ser converter library, 1 per ROOT
dictionary).
"""

import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cmakeparse as cp  # noqa: E402
from scan import WORK  # noqa: E402

SOURCE_KINDS = {
    "library",
    "component",
    "executable",
    "tpcnv",
    "poolcnv",
    "sercnv",
    "cmake_library",
}


def package_files(pkgs, files):
    """Map each file to the longest package prefix."""
    pset = set(pkgs)
    out = collections.defaultdict(list)
    for f in files:
        parts = f.split("/")
        for k in range(len(parts) - 1, 0, -1):
            p = "/".join(parts[:k])
            if p in pset:
                out[p].append("/".join(parts[k:]))
                break
    return out


def load():
    with open(os.path.join(WORK, "cmakelists.json")) as f:
        texts = json.load(f)
    with open(os.path.join(WORK, "srcfiles.txt")) as f:
        files = [ln.rstrip("\n") for ln in f if ln.strip()]
    return texts, files


def analyse(texts, files, config=cp.ATHENA_CONFIG):
    pfiles = package_files(texts, files)
    # pass 1: target names
    names = set()
    for p, t in texts.items():
        ctx = cp.evaluate(p, t, pfiles[p], config, set())
        names.update(x["name"] for x in ctx.targets)
    pkgs = {}
    target_pkg = {}
    for p, t in sorted(texts.items()):
        ctx = cp.evaluate(p, t, pfiles[p], config, names)
        tl = []
        for x in ctx.targets:
            kw = x["kw"]
            srcargs = []
            if x["kind"] in SOURCE_KINDS:
                srcargs = kw.get("", [])[:]
            srcargs += kw.get("SOURCES", [])
            srcs = []
            for a in srcargs:
                srcs.extend(ctx.glob(a))
            srcs = sorted(set(srcs))
            tus = [s for s in srcs if s.endswith(cp.TU_EXT)]
            gen = 0
            if x["kind"] in ("dictionary", "reflex_dictionary", "root_dictionary"):
                gen = 1
            if x["kind"] in ("poolcnv", "sercnv"):
                gen = 1
            rec = {
                "name": x["name"],
                "kind": x["kind"],
                "tus": tus,
                "gen_tus": gen,
                "nsources": len(srcs),
                "links": kw.get("LINK_LIBRARIES", []),
                "private_links": kw.get("PRIVATE_LINK_LIBRARIES", []),
                "includes": kw.get("INCLUDE_DIRS", [])
                + kw.get("PRIVATE_INCLUDE_DIRS", []),
                "interface": "INTERFACE" in kw,
                "public_headers": kw.get("PUBLIC_HEADERS", []),
                "script": bool(kw.get("SCRIPT")),
            }
            if x["kind"] == "test" and not tus and not rec["script"]:
                rec["script"] = True
            tl.append(rec)
            if x["kind"] != "test":
                target_pkg.setdefault(x["name"], p)
        ftxt = t.lower()
        pkgs[p] = {
            "subsystem": p.split("/")[0],
            "targets": tl,
            "find_packages": {k: sorted(v) for k, v in ctx.find_packages.items()},
            "python": "atlas_install_python_modules" in ftxt,
            "scripts": "atlas_install_scripts" in ftxt,
            "joboptions": "atlas_install_joboptions" in ftxt,
            "wrapper_calls": ctx.wrapper_calls,
            "nfiles": len(pfiles[p]),
            "all_cxx": len([f for f in pfiles[p] if f.endswith(cp.TU_EXT)]),
        }
    return pkgs, target_pkg


def main():
    texts, files = load()
    pkgs, target_pkg = analyse(texts, files)
    with open(os.path.join(WORK, "pkgs.json"), "w") as f:
        json.dump(pkgs, f, indent=1, sort_keys=True)
    with open(os.path.join(WORK, "targets.json"), "w") as f:
        json.dump(target_pkg, f, indent=1, sort_keys=True)
    kinds = collections.Counter()
    tus = collections.Counter()
    for p in pkgs.values():
        for t in p["targets"]:
            kinds[t["kind"]] += 1
            tus[t["kind"]] += len(t["tus"])
    print("targets by kind:", dict(kinds))
    print("TUs by kind:", dict(tus))


if __name__ == "__main__":
    main()
