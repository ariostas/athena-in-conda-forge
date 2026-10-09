#!/bin/bash
# xAOD I/O on a DAOD_PHYSLITE file of ATLAS Open Data (2015 data, 132 events, CC0): Athena
# reads it and dumps every object in it (PyDumper), and writes a copy; Athena reads the copy
# back; PyROOT reads both. The dumps must be identical to each other and to the one ATLAS's
# own release writes (data15_physlite.dump.xz), and so must the PyROOT summaries
# (data15_physlite.ref).
set -euxo pipefail

here=$(cd "$(dirname "$0")" && pwd)
input=${1:-opendata/DAOD_PHYSLITE.37001701._000001.pool.root.1}

python "${here}/xaod_rw.py" "${input}" dump_input.txt copy.pool.root
python "${here}/xaod_rw.py" copy.pool.root dump_copy.txt
python - "${here}/data15_physlite.dump.xz" dump_input.txt dump_copy.txt <<'PY'
import difflib, lzma, sys
ref = lzma.open(sys.argv[1], "rt").read().splitlines()
for name in sys.argv[2:]:
    out = open(name).read().splitlines()
    if out != ref:
        sys.stdout.writelines(
            l + "\n" for l in list(difflib.unified_diff(ref, out, "reference", name, lineterm=""))[:100]
        )
        sys.exit(f"{name} differs from the reference dump")
    print(f"{name}: {len(out)} lines, identical to the reference")
PY
python "${here}/read_xaod.py" --ref "${here}/data15_physlite.ref" "${input}" copy.pool.root
