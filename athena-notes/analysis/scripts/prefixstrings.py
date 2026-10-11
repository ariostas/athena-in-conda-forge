"""Kinds of strings containing the host prefix in a layer's shared libraries (outside the
RUNPATH), by what they end with: a census of what packaging rewrites in place, and so of where
a tail-merged string literal could be lost (PLAN.md, M6).

    python3 prefixstrings.py <lib dir> <prefix>

<lib dir> is the lib/ of a kept build tree, <prefix> its host prefix (host_env_placehold...).
"""
import collections
import os
import re
import sys

libdir, pre = sys.argv[1], sys.argv[2].encode()
kinds = collections.Counter()
examples = {}
for f in sorted(os.listdir(libdir)):
    if not f.endswith(".so"):
        continue
    d = open(os.path.join(libdir, f), "rb").read()
    for m in re.finditer(rb"[^\x00]*" + re.escape(pre) + rb"[^\x00]*\x00", d):
        s = m.group()[:-1]
        if b":" in s and s.endswith(b"/lib"):
            continue  # RUNPATH (rewritten by patchelf, not padded)
        ext = os.path.splitext(s.split(b"/")[-1])[1].decode("latin-1") or "(" + s.split(b"/")[-1][-12:].decode("latin-1") + ")"
        kinds[ext] += 1
        examples.setdefault(ext, (f, s.replace(pre, b"$PREFIX")[-100:].decode("latin-1")))
for k, n in kinds.most_common():
    print(f"{n:6d} {k:12s} e.g. {examples[k][0]}: {examples[k][1]}")
