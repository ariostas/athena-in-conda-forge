#!/bin/bash

mkdir build
cd build

# Not with conda-forge's -fvisibility-inlines-hidden: GenericFunctions defines clone() of its
# function classes inline in its .cc files (FUNCTION_OBJECT_IMP), so the library must export
# them for any other code to call clone() (e.g. through the operators that compose functions).
# With hidden inlines, users get undefined references to Genfun::<class>::clone().
CXXFLAGS=${CXXFLAGS//-fvisibility-inlines-hidden/}
export CXXFLAGS

cmake ${CMAKE_ARGS} ../CLHEP/ -DCMAKE_INSTALL_PREFIX=${PREFIX}

make -j ${CPU_COUNT}
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR}" != "" ]]; then
make test
fi
make install

