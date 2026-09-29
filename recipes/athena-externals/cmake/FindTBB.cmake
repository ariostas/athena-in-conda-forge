# Replaces AtlasLCG's FindTBB.cmake for conda environments.
#
# conda-forge's TBB ships a CMake configuration, which Gaudi and ROOT load as well. Creating
# the TBB:: targets by hand, as AtlasLCG's module does, clashes with it: TBB's configuration
# refuses to load when only some of its targets exist (conda-forge's TBB also has
# tbbbind_2_5). So use the configuration, and provide the variables that ATLAS packages use.
#
# Defines TBB_FOUND, TBB_INCLUDE_DIR, TBB_INCLUDE_DIRS, TBB_LIBRARIES, TBB_LIBRARY_DIRS,
# TBB_VERSION and TBB_INSTALL_PATH.

set( _quietFlag )
if( TBB_FIND_QUIETLY )
   set( _quietFlag QUIET )
endif()
find_package( TBB CONFIG ${_quietFlag} )
unset( _quietFlag )

if( TBB_FOUND )
   get_target_property( TBB_INCLUDE_DIR TBB::tbb INTERFACE_INCLUDE_DIRECTORIES )
   set( TBB_INCLUDE_DIRS ${TBB_INCLUDE_DIR} )
   set( TBB_LIBRARIES )
   foreach( _comp tbb ${TBB_FIND_COMPONENTS} )
      if( TARGET TBB::${_comp} )
         list( APPEND TBB_LIBRARIES TBB::${_comp} )
      endif()
   endforeach()
   list( REMOVE_DUPLICATES TBB_LIBRARIES )
   unset( _comp )
   get_filename_component( TBB_INSTALL_PATH "${TBB_INCLUDE_DIR}" DIRECTORY )
   set( TBB_LIBRARY_DIRS "${TBB_INSTALL_PATH}/lib" )
endif()

include( FindPackageHandleStandardArgs )
find_package_handle_standard_args( TBB
   REQUIRED_VARS TBB_INCLUDE_DIR TBB_LIBRARIES
   VERSION_VAR TBB_VERSION )
