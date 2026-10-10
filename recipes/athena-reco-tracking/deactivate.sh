# Undo the activate.sh of this layer: restore what the layers' setup.sh changed.
# The loops below rely on word splitting, which zsh only does with shwordsplit. (conda-forge's
# zsh has an empty ZSH_VERSION.)
if [ -n "${ZSH_VERSION:-}${ZSH_NAME:-}" ] && [[ ! -o shwordsplit ]]; then
  setopt shwordsplit
  _athena_unsetshwordsplit=1
fi

if [ -n "${_ATHENA_SAVED_VARS:-}" ]; then
  for _v in ${_ATHENA_SAVED_VARS}; do
    eval "_val=\"\${_ATHENA_SAVED_${_v}}\""
    if [ "${_val}" = _ATHENA_UNSET_ ]; then
      unset "${_v}"
    else
      export "${_v}=${_val}"
    fi
    unset "_ATHENA_SAVED_${_v}"
  done
  unset _ATHENA_SAVED_VARS _v _val
fi
# conda has already removed the environment's bin/ from PATH, but setup.sh added more entries
# under the environment (and bin/ once more). CONDA_PREFIX is still the environment here.
_athena_path=
_athena_ifs=${IFS}
IFS=:
for _d in ${PATH}; do
  case "${_d}" in
    ""|"${CONDA_PREFIX}"/*) ;;
    *) _athena_path=${_athena_path:+${_athena_path}:}${_d} ;;
  esac
done
IFS=${_athena_ifs}
export PATH="${_athena_path}"
unset _athena_path _athena_ifs _d
# setup.sh also exports <project>_DIR, _PLATFORM, _SET_UP and _VERSION for each project: this
# layer's and every one below it.
for _p in "${CONDA_PREFIX}"/opt/athena/*; do
  _p=${_p##*/}
  unset "${_p}_DIR" "${_p}_PLATFORM" "${_p}_SET_UP" "${_p}_VERSION"
done
if [ -n "${_athena_unsetshwordsplit:-}" ]; then
  unsetopt shwordsplit
  unset _athena_unsetshwordsplit
fi
unset _p
