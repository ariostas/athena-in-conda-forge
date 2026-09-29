"""CPU time and peak memory of the compile jobs of a layer build.

    python3 compile_cost.py <build dir> [--sample N] [--jobs J] [--out costs.json]

<build dir> is the CMake build directory of a layer, kept by rattler-build
(KEEP_BUILD=1 athena-notes/build-local.sh ...): its work/build. Run inside the container,
where the build and host prefixes of that build still exist.

Two sources:
  - .ninja_log: the wall time of every build edge of the real build (compiles, dictionary
    generation, links, genconf, ...), summarised per kind;
  - re-running a sample of the compile commands (ninja -t compdb) one by one, which gives the
    CPU time and the peak resident memory of each (os.wait4), i.e. what bounds the -j of a
    build on a runner with little memory.
python3 stdlib only.
"""

import argparse
import collections
import concurrent.futures
import json
import os
import random
import re
import subprocess


def edge_kind(output):
    if re.search(
        r"(Dict|_rdict|ReflexDict|Dictionary)\w*\.(cxx|cpp)\.o$", output
    ) or re.search(r"/\w+(Dict|Dictionary)\w*\.cxx\.o$", output):
        return "compile (dictionary)"
    if output.endswith(".o"):
        return "compile"
    if output.endswith((".so", ".exe")) or "/bin/" in output:
        return "link"
    if output.endswith((".confdb", ".confdb2", "Conf.py", ".components")):
        return "genconf/components"
    if output.endswith(("Dict.cxx", "_rdict.pcm", ".rootmap", "ReflexDict.cxx")):
        return "dictionary generation"
    return "other"


def ninja_log(build):
    """{output: seconds} of the last run of each edge."""
    fn = os.path.join(build, ".ninja_log")
    out = {}
    with open(fn) as f:
        for line in f:
            if line.startswith("#"):
                continue
            start, end, _mtime, output, _hash = line.rstrip("\n").split("\t")
            out[output] = (int(end) - int(start)) / 1000
    return out


def run_one(entry):
    # some commands are shell snippets ("cd ... && ...")
    args = entry.get("arguments") or ["/bin/bash", "-c", entry["command"]]
    proc = subprocess.Popen(
        args,
        cwd=entry["directory"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    _pid, status, ru = os.wait4(proc.pid, 0)
    return {
        "file": entry["file"],
        "output": entry.get("output", ""),
        "cpu_s": ru.ru_utime + ru.ru_stime,
        "maxrss_mb": ru.ru_maxrss / 1024,
        "status": status,
    }


def pct(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, int(q * len(values)))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("build")
    ap.add_argument("--sample", type=int, default=150)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out")
    a = ap.parse_args()

    times = ninja_log(a.build)
    by_kind = collections.defaultdict(list)
    for output, t in times.items():
        by_kind[edge_kind(output)].append(t)
    print(
        f"ninja log: {len(times)} edges, {sum(times.values()) / 3600:.2f} h summed wall time"
    )
    for kind, ts in sorted(by_kind.items(), key=lambda kv: -sum(kv[1])):
        print(
            f"  {kind:24} {len(ts):5} edges  {sum(ts) / 3600:6.2f} h  "
            f"median {pct(ts, 0.5):6.1f} s  p90 {pct(ts, 0.9):6.1f} s  max {max(ts):6.1f} s"
        )

    compdb = json.loads(
        subprocess.run(
            ["ninja", "-C", a.build, "-t", "compdb"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    )
    compdb = [
        e for e in compdb if e["file"].endswith((".cxx", ".cpp", ".cc", ".C", ".c"))
    ]
    random.seed(a.seed)
    sample = random.sample(compdb, min(a.sample, len(compdb)))
    # the slowest compiles of the real build as well: they are the memory-hungry ones
    slow = sorted(
        (e for e in compdb if e.get("output") in times),
        key=lambda e: -times[e["output"]],
    )[:20]
    todo = {e["file"]: e for e in sample + slow}
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        res = list(ex.map(run_one, todo.values()))
    ok = [r for r in res if r["status"] == 0]
    rss = [r["maxrss_mb"] for r in ok]
    cpu = [r["cpu_s"] for r in ok]
    print(
        f"re-run {len(ok)}/{len(res)} compiles ({len(sample)} random, {len(slow)} slowest): "
        f"peak RSS median {pct(rss, 0.5):.0f} MB, p90 {pct(rss, 0.9):.0f} MB, "
        f"max {max(rss):.0f} MB; CPU median {pct(cpu, 0.5):.1f} s, p90 {pct(cpu, 0.9):.1f} s"
    )
    for r in sorted(ok, key=lambda r: -r["maxrss_mb"])[:10]:
        print(
            f"  {r['maxrss_mb']:6.0f} MB {r['cpu_s']:6.1f} s  {r['file'].split('/work/')[-1]}"
        )
    if a.out:
        with open(a.out, "w") as f:
            json.dump({"ninja_log": times, "compiles": res}, f, indent=1)


if __name__ == "__main__":
    main()
