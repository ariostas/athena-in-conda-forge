# Replaces AtlasLCG's FindFastJetContrib.cmake for conda environments.
#
# LCG builds each FastJet contrib as a library of its own (libNsubjettiness, libVariableR, ...),
# and the components of AtlasLCG's module are those libraries. conda-forge's fastjet-contrib
# has all of them in one shared library, libfastjetcontribfragile: every component is that.
#
# Defines FASTJETCONTRIB_FOUND, FASTJETCONTRIB_INCLUDE_DIR, FASTJETCONTRIB_INCLUDE_DIRS,
# FASTJETCONTRIB_LIBRARIES, FASTJETCONTRIB_LIBRARY_DIRS and FASTJETCONTRIB_<component>_FOUND.

find_path( FASTJETCONTRIB_INCLUDE_DIR fastjet/contrib/Nsubjettiness.hh
   DOC "Path to the FastJet contrib headers" )
find_library( FASTJETCONTRIB_LIBRARY fastjetcontribfragile
   DOC "The FastJet contrib library" )
mark_as_advanced( FASTJETCONTRIB_INCLUDE_DIR FASTJETCONTRIB_LIBRARY )

set( FASTJETCONTRIB_INCLUDE_DIRS ${FASTJETCONTRIB_INCLUDE_DIR} )
set( FASTJETCONTRIB_LIBRARIES ${FASTJETCONTRIB_LIBRARY} )
if( FASTJETCONTRIB_LIBRARY )
   get_filename_component( FASTJETCONTRIB_LIBRARY_DIRS "${FASTJETCONTRIB_LIBRARY}"
      DIRECTORY )
   foreach( _comp ${FastJetContrib_FIND_COMPONENTS} )
      set( FASTJETCONTRIB_${_comp}_FOUND TRUE )
   endforeach()
   unset( _comp )
endif()

include( FindPackageHandleStandardArgs )
find_package_handle_standard_args( FastJetContrib DEFAULT_MSG
   FASTJETCONTRIB_INCLUDE_DIR FASTJETCONTRIB_LIBRARIES )
mark_as_advanced( FASTJETCONTRIB_FOUND FASTJETCONTRIB_INCLUDE_DIRS FASTJETCONTRIB_LIBRARIES
   FASTJETCONTRIB_LIBRARY_DIRS )
