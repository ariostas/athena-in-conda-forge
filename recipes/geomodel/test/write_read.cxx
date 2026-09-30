// A small geometry (a world box holding a steel box with an air box inside) written to a
// GeoModel SQLite file and read back.
#include "GeoModelIOHelpers/GMIO.h"
#include "GeoModelKernel/GeoBox.h"
#include "GeoModelKernel/GeoElement.h"
#include "GeoModelKernel/GeoLogVol.h"
#include "GeoModelKernel/GeoMaterial.h"
#include "GeoModelKernel/GeoNameTag.h"
#include "GeoModelKernel/GeoPhysVol.h"
#include "GeoModelKernel/Units.h"

#include <cstdio>
#include <iostream>
#include <string>

namespace u = GeoModelKernelUnits;

int main(int argc, char* argv[]) {
  const std::string path = argc > 1 ? argv[1] : "geometry.db";
  std::remove(path.c_str());

  auto* iron = new GeoElement("Iron", "Fe", 26.0, 55.847 * u::gram / u::mole);
  auto* nitrogen = new GeoElement("Nitrogen", "N", 7.0, 14.0067 * u::gram / u::mole);
  auto* steel = new GeoMaterial("Steel", 7.9 * u::gram / u::cm3);
  steel->add(iron, 1.0);
  steel->lock();
  auto* air = new GeoMaterial("Air", 0.001214 * u::gram / u::cm3);
  air->add(nitrogen, 1.0);
  air->lock();

  auto* world = new GeoPhysVol(new GeoLogVol("World", new GeoBox(1 * u::m, 1 * u::m, 1 * u::m), air));
  auto* outer = new GeoPhysVol(new GeoLogVol("Outer", new GeoBox(50 * u::cm, 50 * u::cm, 50 * u::cm), steel));
  auto* inner = new GeoPhysVol(new GeoLogVol("Inner", new GeoBox(40 * u::cm, 40 * u::cm, 40 * u::cm), air));
  outer->add(inner);
  world->add(new GeoNameTag("Toy"));
  world->add(outer);

  GeoModelIO::IO::saveToDB(world, path, 0, true);

  PVConstLink read = GeoModelIO::IO::loadDB(path);
  const auto nChildren = read->getNChildVols();
  const auto& outerRead = read->getChildVol(0);
  const auto* box = dynamic_cast<const GeoBox*>(outerRead->getLogVol()->getShape());
  std::cout << "world: " << read->getLogVol()->getName() << ", " << nChildren << " child, "
            << outerRead->getLogVol()->getName() << " made of "
            << outerRead->getLogVol()->getMaterial()->getName() << ", half-length "
            << (box ? box->getXHalfLength() / u::cm : -1) << " cm, "
            << outerRead->getNChildVols() << " child "
            << outerRead->getChildVol(0)->getLogVol()->getName() << std::endl;
  const bool ok = read->getLogVol()->getName() == "World" && nChildren == 1 &&
                  outerRead->getLogVol()->getName() == "Outer" &&
                  outerRead->getLogVol()->getMaterial()->getName() == "Steel" && box &&
                  box->getXHalfLength() == 50 * u::cm && outerRead->getNChildVols() == 1 &&
                  outerRead->getChildVol(0)->getLogVol()->getName() == "Inner";
  return ok ? 0 : 1;
}
