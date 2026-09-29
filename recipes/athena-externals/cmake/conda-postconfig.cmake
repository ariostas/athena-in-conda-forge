
# conda-forge settings, appended to AthenaExternals' PostConfig.cmake so that every project
# built on top of it (all Athena layers, and a user's WorkDir) picks them up.

# With conda-forge's default sysroot (glibc 2.17, which a user's own build may well use) the
# pthread functions are not in libc yet, and plenty of packages use std::thread without
# declaring a dependency on Threads.
find_package( Threads REQUIRED )
link_libraries( Threads::Threads )

# About 180 packages ask for "pthread" as a ROOT component, and AtlasLCG's FindROOT then looks
# for a libpthread, finding the one in root_base's (glibc 2.17) sysroot in the host prefix. Its
# linker script points at /lib64/libpthread.so.0, which does not exist in the build sysroot.
set( ROOT_pthread_LIBRARY "pthread" CACHE FILEPATH "pthread (not a ROOT component)" )
