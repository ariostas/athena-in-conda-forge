"""Identifiers encoded and decoded with the ID dictionaries of the release, through PyROOT.

A port of ATLAS's SCT_ID and PixelID unit tests (InnerDetector/InDetDetDescr/InDetIdentifier):
the dictionaries are XML files found through XMLPATH, and nothing needs a database.
"""

import sys

import ROOT

for lib in ("IdDictParser", "InDetIdentifier"):
    if ROOT.gSystem.Load(f"lib{lib}") < 0:
        sys.exit(f"cannot load lib{lib}")
for header in ("IdDictParser/IdDictParser.h", "InDetIdentifier/SCT_ID.h",
               "InDetIdentifier/PixelID.h"):
    if not ROOT.gInterpreter.Declare(f'#include "{header}"'):
        sys.exit(f"cannot include {header}")

parser = ROOT.IdDictParser()
parser.register_external_entity(
    "InnerDetector", "InDetIdDictFiles/IdDictInnerDetector_IBL3D25-03.xml")
idd = parser.parse("IdDictParser/ATLAS_IDS.xml")

failures = 0


def check(ok, what):
    global failures
    print(("ok: " if ok else "FAILED: ") + what)
    failures += not ok


sct = ROOT.SCT_ID()
check(sct.initialize_from_dictionary(idd) == 0, "SCT_ID from the dictionary")
module = sct.module_id(0, 3, 3, -1)
print("SCT module (0, 3, 3, -1):", hex(module.get_compact()), sct.show_to_string(module))
# the value of ATLAS's own test
check(module.get_compact() == 0xa61a80000000000, "SCT module identifier")
check((sct.barrel_ec(module), sct.layer_disk(module), sct.phi_module(module),
       sct.eta_module(module)) == (0, 3, 3, -1), "SCT module fields decoded")
strip = sct.strip_id(0, 3, 3, -1, 1, 700)
check((sct.side(strip), sct.strip(strip)) == (1, 700) and sct.module_id(strip) == module,
      "SCT strip in its module")
check(sct.wafer_hash_max() == 8176, "8176 SCT wafers")

pixel = ROOT.PixelID()
check(pixel.initialize_from_dictionary(idd) == 0, "PixelID from the dictionary")
wafer = pixel.wafer_id(0, 1, 5, -2)
check((pixel.barrel_ec(wafer), pixel.layer_disk(wafer), pixel.phi_module(wafer),
       pixel.eta_module(wafer)) == (0, 1, 5, -2), "pixel module fields decoded")
check(pixel.wafer_hash_max() == 2048, "2048 pixel modules (with the IBL)")

sys.exit(1 if failures else 0)
