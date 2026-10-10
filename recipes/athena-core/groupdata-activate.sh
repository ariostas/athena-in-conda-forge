# ATLAS's calibration and configuration files (GroupData), which PathResolver looks up in
# CALIBPATH. PathResolver's own environment (env_setup.sh) puts GroupData there as ATLAS's
# release has it: from CVMFS, EOS, then ATLAS's web servers. Without CVMFS a file is only on
# the web servers, and PathResolver downloads it from there (to the job's working directory)
# only with PATHRESOLVER_ALLOWHTTPDOWNLOAD set.
if [ -z "${PATHRESOLVER_ALLOWHTTPDOWNLOAD+x}" ]; then
  export PATHRESOLVER_ALLOWHTTPDOWNLOAD=1
  export _ATHENA_SET_PATHRESOLVER_ALLOWHTTPDOWNLOAD=1
fi
