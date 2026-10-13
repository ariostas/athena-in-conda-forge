
# conda-forge settings, appended to AthenaExternals' PostConfig.cmake so that every project
# built on top of it (all Athena layers, and a user's WorkDir) picks them up.

# With conda-forge's default sysroot (glibc 2.17, which a user's own build may well use) the
# pthread functions are not in libc yet, and plenty of packages use std::thread without
# declaring a dependency on Threads.
find_package( Threads REQUIRED )
link_libraries( Threads::Threads )

# glibc's libraries by name, not by path. Otherwise find_library finds them in a sysroot: the
# compiler's in the build environment, whose absolute path then ends up in the exported targets
# of every layer (a path that exists only during that build), or root_base's (glibc 2.17) in the
# host prefix, whose libpthread linker script points at /lib64/libpthread.so.0.
# - About 170 packages ask for "pthread" as a ROOT component: AtlasLCG's FindROOT looks it up
#   in _ROOT_pthread_library.
# - CMake's FindHDF5 resolves the libraries of HDF5's compiler wrapper (-ldl -lm) one by one.
set( _ROOT_pthread_library "pthread" CACHE FILEPATH "pthread (not a ROOT component)" )
foreach( _lang C CXX )
   foreach( _lib dl m pthread rt )
      set( HDF5_${_lang}_LIBRARY_${_lib} "${_lib}" CACHE FILEPATH "glibc's lib${_lib}" )
   endforeach()
endforeach()
unset( _lang )
unset( _lib )

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

# On macOS conda-forge's libc++ headers mark library features newer than the deployment target
# as unavailable (std::from_chars for floating point, the time zone database, ...), some even
# in inline code that <chrono> and <format> bring in. The environments have conda-forge's own,
# current libc++ at run time.
if( APPLE )
   add_compile_definitions( _LIBCPP_DISABLE_AVAILABILITY )
endif()

# On macOS, clang turns a dynamic_cast to a final class into a comparison with the address of
# its vtable. A class whose virtual functions are all inline has a vtable in every library that
# uses it, and the linker makes each copy private to its library: a dynamic_cast to it in one
# library then fails for an object made in another (POOL's converters on Pixel1RawData).
if( APPLE )
   add_compile_options( $<$<COMPILE_LANGUAGE:CXX>:-fno-assume-unique-vtables> )
endif()

# On macOS (a case-insensitive file system), ROOT's find_dependency(Vdt) finds AtlasLCG's
# FindVDT.cmake instead of ROOT's FindVdt.cmake. That one creates no VDT::VDT target, and ROOT
# is then not found. ROOT skips the search when the target exists: the one its module creates.
if( APPLE AND NOT TARGET VDT::VDT )
   find_library( _conda_vdt_library NAMES vdt )
   find_path( _conda_vdt_include NAMES vdt/vdtMath.h )
   mark_as_advanced( _conda_vdt_library _conda_vdt_include )
   if( _conda_vdt_library AND _conda_vdt_include )
      add_library( VDT::VDT SHARED IMPORTED )
      set_target_properties( VDT::VDT PROPERTIES
         IMPORTED_LOCATION "${_conda_vdt_library}"
         INTERFACE_INCLUDE_DIRECTORIES "${_conda_vdt_include}" )
   endif()
endif()

# On macOS the libraries that use Python (Gaudi's, and Athena's through AtlasLCG's FindPython)
# look its symbols up in the process instead of linking libpython: conda-forge's python has the
# interpreter built in, and a library linking libpython would run against a second,
# uninitialised copy of it. So every executable loads libpython, also one that uses none of its
# symbols itself (conda-forge's -dead_strip_dylibs would drop it otherwise).
if( APPLE )
   find_package( Python COMPONENTS Development QUIET )
   if( TARGET Python::Python )
      add_link_options( "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:LINKER:-needed_library,$<TARGET_LINKER_FILE:Python::Python>>" )
   endif()
endif()
