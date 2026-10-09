"""List the T/P converter tests (run_tpcnv_test) of the packages of a layer.

    python3 athena-notes/analysis/scripts/tpcnv_tests.py recipes/athena-edm/packages.txt

These are ATLAS's schema evolution tests: each reads a file written by an old release (on
CVMFS), dumps some of its objects with the current classes and compares the dump with a
reference (also on CVMFS). Prints one line per test: package, test name, reference tag
(<package>/<tag>, the ATLAS_REFERENCE_TAG the test needs) and the libraries the test requires.
Reads the packages' CMakeLists.txt from _work/cmakelists.json (scan.py).
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scan import WORK  # noqa: E402

CALL = re.compile(r"^\s*run_tpcnv_test\s*\(([^)]*)\)", re.M)
SET = re.compile(r"^\s*set\s*\(\s*(\w+)\s+([^\s)]+)\s*\)", re.M)


def main():
    with open(sys.argv[1]) as f:
        packages = [line.strip() for line in f if line.strip() and not line.startswith("#")]
    with open(os.path.join(WORK, "cmakelists.json")) as f:
        cmakelists = json.load(f)
    for p in packages:
        text = cmakelists.get(p, "")
        variables = dict(SET.findall(text))
        name = p.rsplit("/", 1)[-1]
        for args in CALL.findall(text):
            words = [variables.get(w[2:-1], w) if w.startswith("${") else w for w in args.split()]
            test = words[0]
            opts = {"REFERENCE_TAG": [], "REQUIRED_LIBRARIES": []}
            key = None
            for w in words[2:]:
                if w in opts:
                    key = w
                elif key:
                    opts[key].append(w)
            tag = f"{name}/{opts['REFERENCE_TAG'][0]}" if opts["REFERENCE_TAG"] else "-"
            print(p, test, tag, *opts["REQUIRED_LIBRARIES"])


if __name__ == "__main__":
    main()
