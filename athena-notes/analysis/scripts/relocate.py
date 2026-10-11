"""Replace a prefix in a binary as conda packaging does: in every NUL-terminated string that
contains it, by a shorter one, padding the string with NULs at its end.

    python3 relocate.py <in> <out> <old prefix> <new prefix>

Run on a library of a kept build tree (old prefix: the build's host prefix, new: an
environment's), it gives the library as packaged, e.g. to tell whether a failure comes from
the build or from packaging (PLAN.md, M6: string tail merging).
"""
import re
import sys

src, dst, old, new = sys.argv[1], sys.argv[2], sys.argv[3].encode(), sys.argv[4].encode()
data = bytearray(open(src, "rb").read())
n = 0
for m in re.finditer(rb"[^\x00]*" + re.escape(old) + rb"[^\x00]*\x00", bytes(data)):
    s = m.group()
    r = s.replace(old, new)
    data[m.start():m.end()] = r + b"\x00" * (len(s) - len(r))
    n += 1
open(dst, "wb").write(data)
print(n, "strings relocated")
