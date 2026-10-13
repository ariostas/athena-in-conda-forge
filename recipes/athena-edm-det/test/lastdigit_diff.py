"""lastdigit_diff.py <log>: compare again the dump and the reference of a T/P converter test
whose log reports "ERROR running diff with reference" (the diff's header names both files),
allowing numbers to differ by one unit in their last printed digit. Exit code 0 if they agree.

For macOS: its math library rounds some results differently from glibc's, and a quantity
that comes out of a cancellation (the mass of a 360 GeV pion from its energy and momentum)
can then differ in its last printed digit from ATLAS's reference.
"""

import re
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path

log = Path(sys.argv[1])
ref = dump = None
for line in log.read_text(errors="replace").splitlines():
    if line.startswith("--- ") and ref is None:
        ref = Path(line[4:].split("\t")[0])
    elif line.startswith("+++ ") and dump is None:
        dump = Path(line[4:].split("\t")[0])
if ref is None or dump is None:
    sys.exit(f"{log}: no diff header")
if not dump.is_absolute():
    dump = log.parent / dump


def close(a, b):
    try:
        x, y = Decimal(a), Decimal(b)
    except InvalidOperation:
        return False
    exp = x.as_tuple().exponent
    return exp == y.as_tuple().exponent and abs(x - y) <= Decimal(1).scaleb(exp)


number = re.compile(r"^[-+]?\d+\.\d+$")
ref_lines = ref.read_text(errors="replace").splitlines()
dump_lines = dump.read_text(errors="replace").splitlines()
if len(ref_lines) != len(dump_lines):
    sys.exit(f"{dump}: {len(dump_lines)} lines, the reference has {len(ref_lines)}")
ndiff = 0
for n, (r, d) in enumerate(zip(ref_lines, dump_lines), 1):
    if r == d:
        continue
    rt, dt = r.split(), d.split()
    if len(rt) != len(dt) or not all(
        u == v or (number.match(u) and number.match(v) and close(u, v)) for u, v in zip(rt, dt)
    ):
        sys.exit(f"{dump}:{n} differs from the reference:\n- {r}\n+ {d}")
    ndiff += 1
print(f"{dump}: {ndiff} line(s) differ from the reference in the last digit only")
