# Set up the @LAYER@ layer of Athena with its own setup.sh, which also sets up the layers
# below it. Provisional: PLAN.md D6 replaces setup.sh with plain activation scripts.
#
# The loops below rely on word splitting, which zsh only does with shwordsplit. (conda-forge's
# zsh has an empty ZSH_VERSION.)
if [ -n "${ZSH_VERSION:-}${ZSH_NAME:-}" ] && [[ ! -o shwordsplit ]]; then
  setopt shwordsplit
  _athena_unsetshwordsplit=1
fi

# setup.sh changes these variables; save them for deactivate.sh. (PATH is handled there
# separately: conda has already restored its own view of it when deactivate.sh runs.)
_athena_vars="LD_LIBRARY_PATH DYLD_LIBRARY_PATH PYTHONPATH PYTHONHOME ROOT_INCLUDE_PATH
  CMAKE_PREFIX_PATH JOBOPTSEARCHPATH DATAPATH CALIBPATH XMLPATH CMTCONFIG LCG_RELEASE_BASE
  GFORTRAN_UNBUFFERED_ALL"
if [ -z "${_ATHENA_SAVED_VARS:-}" ]; then
  for _v in ${_athena_vars}; do
    if eval "[ -n \"\${${_v}+x}\" ]"; then
      eval "export _ATHENA_SAVED_${_v}=\"\${${_v}}\""
    else
      eval "export _ATHENA_SAVED_${_v}=_ATHENA_UNSET_"
    fi
  done
  export _ATHENA_SAVED_VARS="${_athena_vars}"
fi
unset _v _athena_vars

# (setup.sh is not written for "set -u")
case "$-" in *u*) _athena_nounset=1; set +u ;; esac
. "${CONDA_PREFIX}/opt/athena/@LAYER@/@VERSION@/InstallArea/@PLATFORM@/setup.sh" > /dev/null
[ -n "${_athena_nounset:-}" ] && set -u
unset _athena_nounset

# Not wanted in a conda environment: the conda python is the one in PATH anyway, and there is
# no LCG release.
[ "${_ATHENA_SAVED_PYTHONHOME}" = _ATHENA_UNSET_ ] && unset PYTHONHOME
[ "${_ATHENA_SAVED_LCG_RELEASE_BASE}" = _ATHENA_UNSET_ ] && unset LCG_RELEASE_BASE
if [ -n "${_athena_unsetshwordsplit:-}" ]; then
  unsetopt shwordsplit
  unset _athena_unsetshwordsplit
fi
true
