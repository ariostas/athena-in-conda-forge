
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

# AtlasLCG's FindROOT requires ROOT's python modules, and looks for them in <ROOT>/lib:
# conda-forge has them in site-packages. Without them ROOT_FOUND is false, which goes unnoticed
# until a package asks for ROOT with REQUIRED.
if( NOT ROOT_PYTHON_PATH )
   string( REPLACE ":" ";" _prefixes "$ENV{CMAKE_PREFIX_PATH}" )
   foreach( _prefix ${CMAKE_PREFIX_PATH} ${_prefixes} $ENV{CONDA_PREFIX} )
      file( GLOB _rootpy "${_prefix}/lib/python3*/site-packages/ROOT/__init__.py" )
      if( _rootpy )
         list( GET _rootpy 0 _rootpy )
         get_filename_component( _rootpy "${_rootpy}" DIRECTORY )
         get_filename_component( _rootpy "${_rootpy}" DIRECTORY )
         set( ROOT_PYTHON_PATH "${_rootpy}" CACHE PATH "Path to the ROOT python module(s)"
            FORCE )
         break()
      endif()
   endforeach()
   unset( _prefixes )
   unset( _prefix )
   unset( _rootpy )
endif()
