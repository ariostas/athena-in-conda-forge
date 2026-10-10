#!/usr/bin/env bash
set -eux

test "$(clhep-config --version)" = "CLHEP ${CLHEP_VERSION}"
clhep-config --prefix
clhep-config --include
clhep-config --libs

# Consumers locate CLHEP through the CMake package it installs -- Geant4 does
# find_package(CLHEP <version> EXACT CONFIG) and welds every one of its own
# consumers to the result -- so drive that path rather than only checking the
# files are present. Compiling against the installed headers is also the only
# thing that catches a header which no longer builds with the current compiler.
mkdir cmake-test
cd cmake-test

cat > CMakeLists.txt <<EOF
cmake_minimum_required(VERSION 3.20)
project(clhep_smoke CXX)
find_package(CLHEP ${CLHEP_VERSION} EXACT REQUIRED CONFIG)
add_executable(clhep_smoke clhep_smoke.cc)
target_link_libraries(clhep_smoke CLHEP::CLHEP)
EOF

cat > clhep_smoke.cc <<'EOF'
#include <cmath>
#include <cstdio>

#include "CLHEP/Random/MixMaxRng.h"
#include "CLHEP/Units/SystemOfUnits.h"
#include "CLHEP/Vector/LorentzVector.h"

#define CHECK(cond)                                                     \
  do {                                                                  \
    if (!(cond)) {                                                      \
      std::fprintf(stderr, "FAILED: %s (line %d)\n", #cond, __LINE__);  \
      return 1;                                                         \
    }                                                                   \
  } while (0)

int main() {
  // MixMaxRng is the engine Geant4 defaults to, and its header is the one that
  // needs <cstdint>.
  CLHEP::MixMaxRng rng(1234);
  double sum = 0.0;
  for (int i = 0; i < 10000; ++i) {
    const double u = rng.flat();
    CHECK(u > 0.0 && u <= 1.0);
    sum += u;
  }
  CHECK(std::fabs(sum / 10000.0 - 0.5) < 0.02);

  // A boost has to leave the invariant mass alone.
  const double m = 938.272 * CLHEP::MeV;
  const double pz = 1.0 * CLHEP::GeV;
  CLHEP::HepLorentzVector p(0.0, 0.0, pz, std::sqrt(pz * pz + m * m));
  const double m_before = p.m();
  p.boostZ(0.5);
  CHECK(std::fabs(p.m() - m_before) < 1e-6 * m_before);

  CHECK(std::fabs(CLHEP::GeV / CLHEP::MeV - 1000.0) < 1e-9);

  std::printf("ok\n");
  return 0;
}
EOF

cmake -S . -B build ${CMAKE_ARGS:-} -DCMAKE_BUILD_TYPE=Release
cmake --build build
test "$(./build/clhep_smoke)" = "ok"
