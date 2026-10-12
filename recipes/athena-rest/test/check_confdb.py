"""Check that every component in a .components file has a configurable.

genconf instantiates every component at build time to write its configurable. If it crashes
on a library (for instance when Gaudi and the component were built with different compilers),
the build carries on and the configurables of that library are simply missing.

usage: python check_confdb.py <file.components> [<allowed missing name> ...]
"""

import re
import sys

from GaudiKernel.ConfigurableDb import cfgDb, loadConfigurableDb

# Components that are not configurable: converters (and the _PERS_/_TRANS_ aliases of the
# T/P converters), interface ids, POOL's ROOT storage technologies, and one factory. With these
# rules every component of ATLAS's own Athena 25.0.73 release has a configurable.
NOT_CONFIGURABLE = re.compile(
    r"\d+|CNV_\d+_\d+|IID_\d+|_[A-Z].*|.*(Cnv|Converter).*|ROOT_\w+"
    r"|RootAuxDynIO(::|__)FactoryTool"
)


def configurable_name(name):
    """The name genconf gives the configurable of a component."""
    return re.sub(r"[<>:,]", "_", name.replace(" ", ""))


loadConfigurableDb()
components = set()
with open(sys.argv[1]) as f:
    for line in f:
        line = line.split("#", 1)[0].strip()
        if line:
            components.add(line.removeprefix("v2::").split(":", 1)[1])
allowed = {configurable_name(name) for name in sys.argv[2:]}
missing = sorted(
    name
    for name in components
    if not NOT_CONFIGURABLE.fullmatch(name)
    and configurable_name(name) not in allowed
    and configurable_name(name) not in cfgDb
)
print(f"{len(components)} components, {len(cfgDb)} configurables")
if missing:
    print("components without a configurable:", *missing, sep="\n  ")
    sys.exit(1)
