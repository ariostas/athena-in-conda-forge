"""Cache the raw inputs of the package analysis from the Athena install area on CVMFS.

Reads every package's CMakeLists.txt (packages.txt gives the list) and the list of files under
src/, and writes them to _work/ so the other scripts never touch CVMFS again:

    _work/cmakelists.json   {package: CMakeLists.txt text}
    _work/srcfiles.txt      every file under src/, relative to src/

    python3 athena-notes/analysis/scripts/scan.py [--release DIR]
"""

import argparse
import json
import os

RELEASE = (
    "/cvmfs/atlas.cern.ch/repo/sw/software/25.0/Athena/25.0.73/InstallArea/"
    "aarch64-el9-gcc15-opt"
)
WORK = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "_work"
)
WORK = os.path.normpath(WORK)


def read_packages(release):
    with open(os.path.join(release, "packages.txt")) as f:
        return [ln.split()[0] for ln in f if ln.strip() and not ln.startswith("#")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--release", default=RELEASE)
    ap.add_argument("--out", default="cmakelists.json")
    ap.add_argument("--files", default="srcfiles.txt")
    a = ap.parse_args()
    os.makedirs(WORK, exist_ok=True)
    src = os.path.join(a.release, "src")
    pkgs = read_packages(a.release)
    texts = {}
    for p in pkgs:
        fn = os.path.join(src, p, "CMakeLists.txt")
        try:
            with open(fn, errors="replace") as f:
                texts[p] = f.read()
        except OSError:
            texts[p] = None
    with open(os.path.join(WORK, a.out), "w") as f:
        json.dump(texts, f, indent=0, sort_keys=True)
    files = []
    for root, dirs, fns in os.walk(src):
        rel = os.path.relpath(root, src)
        for fn in fns:
            files.append(os.path.normpath(os.path.join(rel, fn)))
    files.sort()
    with open(os.path.join(WORK, a.files), "w") as f:
        f.write("\n".join(files) + "\n")
    print(
        f"{len(pkgs)} packages, {sum(t is None for t in texts.values())} without "
        f"CMakeLists.txt, {len(files)} files"
    )


if __name__ == "__main__":
    main()
