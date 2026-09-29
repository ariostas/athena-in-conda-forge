# Replacement for AtlasCMake's Findtdaq-common.cmake, for conda-forge's tdaq-common: the
# headers, libraries and python modules are in the environment's standard places, not in a
# tdaq release area (installed/include, installed/<platform>/lib, installed/share/lib/python),
# and there is no TDAQ environment (TDAQ_RELEASE_BASE, TDAQ_PYTHON_HOME, TDAQ_PLATFORM) to set.
#
# Defines:
#  - TDAQ-COMMON_FOUND
#  - TDAQ-COMMON_INCLUDE_DIR, TDAQ-COMMON_INCLUDE_DIRS
#  - TDAQ-COMMON_<component>_FOUND, TDAQ-COMMON_<component>_LIBRARY
#  - TDAQ-COMMON_LIBRARIES, TDAQ-COMMON_LIBRARY_DIRS

include( AtlasInternals )

atlas_external_module( NAME tdaq-common
   INCLUDE_SUFFIXES include INCLUDE_NAMES eformat/eformat.h
   LIBRARY_SUFFIXES lib
   COMPULSORY_COMPONENTS eformat ers )

include( FindPackageHandleStandardArgs )
find_package_handle_standard_args( tdaq-common DEFAULT_MSG
   TDAQ-COMMON_INCLUDE_DIR TDAQ-COMMON_LIBRARIES )
mark_as_advanced( TDAQ-COMMON_FOUND TDAQ-COMMON_INCLUDE_DIR
   TDAQ-COMMON_INCLUDE_DIRS TDAQ-COMMON_LIBRARIES TDAQ-COMMON_LIBRARY_DIRS )
