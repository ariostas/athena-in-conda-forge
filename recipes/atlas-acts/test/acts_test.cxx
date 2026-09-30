// A few checks across the components Athena uses: a surface written to JSON and read back
// (PluginJson), a straight line intersected with it (Core), and a GeoModel material converted
// to an ACTS one (PluginGeoModel).
#include "Acts/Definitions/Algebra.hpp"
#include "Acts/Definitions/Units.hpp"
#include "Acts/Geometry/GeometryContext.hpp"
#include "Acts/Surfaces/PlaneSurface.hpp"
#include "Acts/Surfaces/RectangleBounds.hpp"
#include "ActsPlugins/GeoModel/GeoModelMaterialConverter.hpp"
#include "ActsPlugins/Json/SurfaceJsonConverter.hpp"

#include "GeoModelKernel/GeoElement.h"
#include "GeoModelKernel/GeoMaterial.h"
#include "GeoModelKernel/Units.h"

#include <cmath>
#include <iostream>
#include <memory>

#include <nlohmann/json.hpp>

int main() {
  using namespace Acts::UnitLiterals;
  auto gctx = Acts::GeometryContext::dangerouslyDefaultConstruct();
  int failures = 0;
  auto check = [&failures](bool ok, const char* what) {
    std::cout << (ok ? "ok: " : "FAILED: ") << what << std::endl;
    failures += !ok;
  };

  // a 20 cm x 10 cm plane at z = 1 m
  Acts::Transform3 trf(Acts::Transform3::Identity() * Acts::Translation3(0., 0., 1_m));
  auto plane = Acts::Surface::makeShared<Acts::PlaneSurface>(
      trf, std::make_shared<Acts::RectangleBounds>(10_cm, 5_cm));
  nlohmann::json j = Acts::SurfaceJsonConverter::toJson(gctx, *plane);
  auto back = Acts::SurfaceJsonConverter::fromJson(nlohmann::json::parse(j.dump()));
  check(back->bounds() == plane->bounds() &&
            back->localToGlobalTransform(gctx).isApprox(plane->localToGlobalTransform(gctx)),
        "plane surface JSON round trip");

  // a line from the origin at 45 degrees in x-z hits it at x = 1 m, outside the bounds
  auto dir = Acts::Vector3(1., 0., 1.).normalized();
  auto hit = back->intersect(gctx, Acts::Vector3::Zero(), dir).closest();
  check(std::abs(hit.pathLength() - std::sqrt(2.) * 1_m) < 1e-6 &&
            std::abs(hit.position().x() - 1_m) < 1e-6,
        "straight line intersection");
  auto inside = back->intersect(gctx, Acts::Vector3::Zero(), dir,
                                Acts::BoundaryTolerance::None()).closest();
  check(!inside.isValid(), "intersection outside the bounds is rejected");

  // iron: X0 = 17.57 mm
  auto* fe = new GeoElement("Iron", "Fe", 26., 55.845 * GeoModelKernelUnits::gram /
                                                   GeoModelKernelUnits::mole);
  auto* iron = new GeoMaterial("Iron", 7.874 * GeoModelKernelUnits::gram /
                                           GeoModelKernelUnits::cm3);
  iron->add(fe, 1.);
  iron->lock();
  auto m = ActsPlugins::GeoModel::geoMaterialConverter(*iron);
  std::cout << "iron X0 = " << m.X0() / 1_mm << " mm, L0 = " << m.L0() / 1_mm << " mm"
            << std::endl;
  check(std::abs(m.X0() / 1_mm - 17.57) < 0.5, "GeoModel material conversion");

  return failures == 0 ? 0 : 1;
}
