// Links the static libraries, builds a VecGeom polycone, a NIST material and ATLAS's RK4
// stepper, and prints the version.
#include "G4AtlasRK4.hh"
#include "G4Box.hh"
#include "G4Mag_UsualEqRhs.hh"
#include "G4NistManager.hh"
#include "G4Polycone.hh"
#include "G4SystemOfUnits.hh"
#include "G4ThreeVector.hh"
#include "G4UniformMagField.hh"
#include "G4Version.hh"

#include <iostream>

int main() {
  G4Material* lar = G4NistManager::Instance()->FindOrBuildMaterial("G4_lAr");
  const G4double z[] = {-10 * cm, 10 * cm};
  const G4double rmin[] = {1 * cm, 1 * cm};
  const G4double rmax[] = {5 * cm, 6 * cm};
  G4Polycone pcon("pcon", 0, CLHEP::twopi, 2, z, rmin, rmax);
  G4Box box("box", 1 * m, 1 * m, 1 * m);
  G4UniformMagField field(G4ThreeVector(0, 0, 2 * tesla));
  G4Mag_UsualEqRhs equation(&field);
  G4AtlasRK4 stepper(&equation);
  const G4double v = pcon.GetCubicVolume();
  std::cout << G4Version << " " << lar->GetName() << " polycone " << v / cm3 << " cm3"
            << std::endl;
  return (v > 0 && box.Inside(G4ThreeVector()) == kInside) ? 0 : 1;
}
