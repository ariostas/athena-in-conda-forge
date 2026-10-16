
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

# On macOS, look for frameworks and app bundles after everything else, as conda-forge's builds
# do (CMAKE_ARGS), and not in Homebrew's prefixes: in a user's work area (configured without
# conda-forge's CMAKE_ARGS) CMake's FindPython took Homebrew's Python framework, a different
# Python than the environment's, which the layers were built against.
if( APPLE )
   if( NOT DEFINED CMAKE_FIND_FRAMEWORK )
      set( CMAKE_FIND_FRAMEWORK LAST )
   endif()
   if( NOT DEFINED CMAKE_FIND_APPBUNDLE )
      set( CMAKE_FIND_APPBUNDLE LAST )
   endif()
   if( NOT DEFINED Python_FIND_FRAMEWORK )
      set( Python_FIND_FRAMEWORK LAST )
   endif()
   list( APPEND CMAKE_SYSTEM_IGNORE_PREFIX_PATH /opt/homebrew /usr/local )
endif()

# On macOS the libraries find each other through rpaths (AtlasCMake patch 0005), which the
# layers' builds give in CMAKE_INSTALL_RPATH. A project built on top of them without one (a
# user's work area) gets its own lib/ first, so that what it rebuilds takes precedence, then
# the lib/ of every installed layer and the environment's lib/.
if( APPLE AND NOT DEFINED CMAKE_INSTALL_RPATH )
   get_filename_component( _conda_platform "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE )
   get_filename_component( _conda_platform "${_conda_platform}" NAME )
   get_filename_component( _conda_athena "${CMAKE_CURRENT_LIST_DIR}/../../../../.." ABSOLUTE )
   file( GLOB _conda_rpath "${_conda_athena}/*/*/InstallArea/${_conda_platform}/lib" )
   set( CMAKE_INSTALL_RPATH "${CMAKE_BINARY_DIR}/${_conda_platform}/lib" ${_conda_rpath}
      "${_conda_athena}/../../lib" )
   unset( _conda_platform )
   unset( _conda_athena )
   unset( _conda_rpath )
endif()

# On macOS a user's work area builds with the system's SDK (the layers with conda-forge's). In
# C++20 and later, the math.h of newer SDKs (macOS 27's) takes INFINITY and NAN from the
# compiler's float.h, asking for them with __need_infinity_nan, which clang knows from version
# 21 on: clang 20's float.h defines them only outside strict ANSI mode (not with -std=c++23), and
# <complex> does not compile.
if( APPLE AND CMAKE_CXX_COMPILER_ID MATCHES "Clang" AND
   CMAKE_CXX_COMPILER_VERSION VERSION_LESS 21 )
   set( _conda_math_h "${CMAKE_OSX_SYSROOT}/usr/include/math.h" )
   if( NOT EXISTS "${_conda_math_h}" )
      set( _conda_math_h "${_CMAKE_OSX_SYSROOT_PATH}/usr/include/math.h" )
   endif()
   if( EXISTS "${_conda_math_h}" )
      file( STRINGS "${_conda_math_h}" _conda_need_infinity_nan REGEX "__need_infinity_nan" )
      if( _conda_need_infinity_nan )
         add_compile_definitions( "$<$<COMPILE_LANGUAGE:CXX>:INFINITY=__builtin_inff()>"
            "$<$<COMPILE_LANGUAGE:CXX>:NAN=__builtin_nanf(\"\")>" )
      endif()
   endif()
   unset( _conda_math_h )
   unset( _conda_need_infinity_nan )
endif()

# On macOS OpenGL is the system's framework. VP1's packages link "GL" by name, which names no
# library there. And FindOpenGL takes an XQuartz libGL (/usr/X11R6) before the framework
# (conda-forge's CMAKE_FIND_FRAMEWORK=LAST), which a user's machine may have and conda-forge's
# environments do not.
if( APPLE )
   list( APPEND CMAKE_SYSTEM_IGNORE_PREFIX_PATH /usr/X11R6 /opt/X11 )
   if( NOT TARGET GL )
      add_library( GL INTERFACE IMPORTED GLOBAL )
      set_target_properties( GL PROPERTIES INTERFACE_LINK_LIBRARIES "-framework OpenGL" )
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
