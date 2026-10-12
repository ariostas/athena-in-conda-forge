# The ROOT functions of the tdaq build system (cmake_tdaq) that dqm_core uses.
#
# tdaq_root_generate_dictionary(<name> <headers> ... [OPTIONS ...] LINKDEF <linkdef>) writes the
# dictionary source <name>.cpp, which the package lists among the sources of its library
# lib<name>, and the library's ROOT module (lib<name>_rdict.pcm) and rootmap, installed next to
# it.
function(tdaq_root_generate_dictionary name)
  cmake_parse_arguments(ARG "" "LINKDEF" "OPTIONS" ${ARGN})
  set(opts)
  foreach(o ${ARG_OPTIONS})
    # include directories of the tdaq-common source tree (ers): installed in the prefix here
    if(o MATCHES "^-I(.*)" AND NOT IS_DIRECTORY "${CMAKE_MATCH_1}")
      continue()
    endif()
    list(APPEND opts ${o})
  endforeach()
  set(out ${CMAKE_CURRENT_BINARY_DIR})
  add_custom_command(
    OUTPUT ${out}/${name}.cpp ${out}/lib${name}_rdict.pcm ${out}/lib${name}.rootmap
    COMMAND ROOT::rootcling -f ${out}/${name}.cpp -s ${out}/lib${name}${CMAKE_SHARED_LIBRARY_SUFFIX}
      -rml lib${name}${CMAKE_SHARED_LIBRARY_SUFFIX} -rmf ${out}/lib${name}.rootmap
      -I${CMAKE_CURRENT_SOURCE_DIR} -I${ERS_INCLUDE_DIR} ${opts}
      ${ARG_UNPARSED_ARGUMENTS} ${ARG_LINKDEF}
    DEPENDS ${ARG_UNPARSED_ARGUMENTS} ${ARG_LINKDEF}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Generating the ROOT dictionary of ${name}")
  install(FILES ${out}/lib${name}_rdict.pcm ${out}/lib${name}.rootmap
    DESTINATION ${CMAKE_INSTALL_LIBDIR})
endfunction()

# The pcm files are written with the dictionaries above.
function(tdaq_add_pcm)
endfunction()
