
# conda-forge settings, appended to AthenaExternals' PostConfig.cmake so that every project
# built on top of it (all Athena layers, and a user's WorkDir) picks them up.

# conda-forge's sysroot is glibc 2.17, where the pthread functions are not in libc yet,
# and plenty of packages use std::thread without declaring a dependency on Threads.
find_package( Threads REQUIRED )
link_libraries( Threads::Threads )
