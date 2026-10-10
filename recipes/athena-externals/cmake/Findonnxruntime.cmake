# Replaces atlasexternals' Findonnxruntime.cmake for conda environments.
#
# ATLAS uses Microsoft's binary release of onnxruntime, with its C and C++ API headers directly
# in include/, and Athena includes them by name (onnxruntime_cxx_api.h). conda-forge's
# onnxruntime-cpp installs them in include/onnxruntime/core/session/, with the rest of the
# headers under include/onnxruntime/: both directories go in the include path.
#
# Defines ONNXRUNTIME_FOUND, ONNXRUNTIME_INCLUDE_DIR, ONNXRUNTIME_INCLUDE_DIRS,
# ONNXRUNTIME_LIBRARIES and ONNXRUNTIME_LIBRARY_DIRS.

find_path( ONNXRUNTIME_INCLUDE_DIR core/session/onnxruntime_cxx_api.h
   PATH_SUFFIXES include/onnxruntime
   DOC "Path to the onnxruntime headers" )
find_library( ONNXRUNTIME_LIBRARY onnxruntime
   DOC "The onnxruntime library" )
mark_as_advanced( ONNXRUNTIME_INCLUDE_DIR ONNXRUNTIME_LIBRARY )

set( ONNXRUNTIME_INCLUDE_DIRS ${ONNXRUNTIME_INCLUDE_DIR}
   ${ONNXRUNTIME_INCLUDE_DIR}/core/session )
set( ONNXRUNTIME_LIBRARIES ${ONNXRUNTIME_LIBRARY} )
if( ONNXRUNTIME_LIBRARY )
   get_filename_component( ONNXRUNTIME_LIBRARY_DIRS "${ONNXRUNTIME_LIBRARY}" DIRECTORY )
endif()

include( FindPackageHandleStandardArgs )
find_package_handle_standard_args( onnxruntime DEFAULT_MSG ONNXRUNTIME_INCLUDE_DIR
   ONNXRUNTIME_LIBRARIES )
mark_as_advanced( ONNXRUNTIME_FOUND ONNXRUNTIME_INCLUDE_DIRS ONNXRUNTIME_LIBRARIES
   ONNXRUNTIME_LIBRARY_DIRS )
