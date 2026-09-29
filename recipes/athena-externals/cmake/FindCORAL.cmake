# Replaces AtlasLCG's FindCORAL.cmake for conda environments.
#
# AtlasLCG's module requires the CORAL server executables, which lcg-coral does not build
# (the server needs Sun RPC and is not used by Athena). Otherwise the same.
#
# Defines CORAL_FOUND, CORAL_INCLUDE_DIR, CORAL_INCLUDE_DIRS, CORAL_<component>_LIBRARY,
# CORAL_<component>_FOUND, CORAL_LIBRARIES, CORAL_LIBRARY_DIRS and CORAL_PYTHON_PATH.

include( LCGFunctions )

lcg_external_module( NAME CORAL
   INCLUDE_SUFFIXES include
   INCLUDE_NAMES RelationalAccess/ConnectionService.h
   LIBRARY_SUFFIXES lib LIBRARY_PREFIX lcg_
   COMPULSORY_COMPONENTS CoralBase )

# coral.py is in site-packages, which the function searches by default.
lcg_python_external_module( NAME CORAL
   PYTHON_NAMES coral.py
   PYTHON_SUFFIXES python )

include( FindPackageHandleStandardArgs )
find_package_handle_standard_args( CORAL DEFAULT_MSG CORAL_INCLUDE_DIR
   CORAL_LIBRARIES _CORAL_PYTHON_PATH )
