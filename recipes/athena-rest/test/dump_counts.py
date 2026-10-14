"""Checks the size of each collection in PyDumper dumps against ATLAS's release.

    python dump_counts.py <counts file> <dump> ...
    python dump_counts.py --write <counts file> <dump> ...

The size of a collection is the number of lines it has in a dump, summed over the events. The
counts file lists them for ATLAS's release, one '<dump> <collection> <lines>' per line. Where
the dumps cannot be compared with ATLAS's (macOS: ATLAS has no release there), this still
catches a job that runs but reconstructs much less, or nothing. Floating point differences
between platforms can move an object across a threshold, so each size may differ from ATLAS's
by 5% (at least 2 lines). With --write, the sizes of the given dumps are written instead.
"""

import collections
import sys


def sizes(path):
    """Lines per collection (the '----------[type/key]----------' headers), over all events."""
    result = collections.Counter()
    collection = None
    with open(path, errors="replace") as f:
        for line in f:
            if line.startswith("==> evt"):
                collection = None
            elif line.startswith("----------["):
                collection = line.strip().strip("-")
                result[collection] += 0
            elif collection is not None and line.strip():
                result[collection] += 1
    return result


def main(argv):
    write = argv[:1] == ["--write"]
    if write:
        argv = argv[1:]
    counts_file, dumps = argv[0], argv[1:]
    if write:
        with open(counts_file, "w") as f:
            for dump in dumps:
                for collection, n in sorted(sizes(dump).items()):
                    f.write(f"{dump} {collection} {n}\n")
        return 0
    expected = collections.defaultdict(dict)
    with open(counts_file) as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                dump, rest = line.rstrip("\n").split(" ", 1)
                collection, n = rest.rsplit(" ", 1)
                expected[dump][collection] = int(n)
    failed = 0
    for dump in dumps:
        if dump not in expected:
            print(f"{dump}: no sizes to compare with")
            failed += 1
            continue
        ours = sizes(dump)
        differ = 0
        for collection, n in expected[dump].items():
            m = ours.get(collection)
            if m is None:
                print(f"{dump}: {collection} is missing")
                differ += 1
            elif abs(m - n) > max(0.05 * n, 2):
                print(f"{dump}: {collection} has {m} lines, ATLAS's release {n}")
                differ += 1
        for collection in sorted(set(ours) - set(expected[dump])):
            print(f"{dump}: {collection} is not in ATLAS's release")
            differ += 1
        if not differ:
            print(f"{dump}: {len(expected[dump])} collections, sizes as in ATLAS's release")
        failed += differ
    if failed:
        print(f"FAILED: {failed} collection sizes differ from ATLAS's release")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
