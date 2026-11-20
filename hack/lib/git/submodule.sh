# shellcheck shell=bash

# git::submodule_require(file)
#
# Checks that a required file (expected to come from a git submodule) exists,
# for use before sourcing it. Pass a file inside the submodule, not the
# submodule's directory: an uninitialized submodule is still an empty
# directory, so only a file inside it shows the submodule was initialized.
# Uses `echo` rather than the logging API, since this guards the case where
# the logging submodule itself hasn't been initialized yet.
#
# Globals:
#   None.
# Arguments:
#   $1   Path to the file to check.
# Outputs:
#   An error to stderr naming the missing file and the fix (`git submodule
#   update --init --recursive`) if $1 is not a file.
# Returns:
#   1 if $1 is unset/empty or is not a file; 0 otherwise.
git::submodule_require() {
  local path="${1:-}"

  # core::fail is not used to avoid a sourcing loop
  # as logging most likely has not been initialized yet.
  [[ -n "$path" ]] || {
    echo "${FUNCNAME[0]}(): path=\$1 cannot be null." >&2
    return 1
  }

  if [[ ! -f "${path}" ]]; then
    local msg="${FUNCNAME[0]}(): not found: ${path}. "
    msg+="Run: git submodule update --init --recursive"
    echo "${msg}" >&2
    return 1
  fi
}
