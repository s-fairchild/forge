# hack/lib/checksum/sha512sum.sh
#
# Wraps the real `sha512sum` coreutils binary with stdin-driven generate/check helpers.
# shellcheck shell=bash

declare -r __hack_lib_checksum_sha512sum_sourced="true"

# sha512sum()
#
# Shadows the coreutils `sha512sum` binary so callers in this tree always go through one
# call site; delegates every argument straight through.
#
# Arguments:
#   $@ - passed verbatim to `command sha512sum`.
# Outputs:
#   Whatever `sha512sum` writes to stdout/stderr.
# Returns:
#   `sha512sum`'s exit status.
sha512sum() {
  command sha512sum "$@"
}

# sha512sum_gen_stdin()
#
# Generates a sha512 checksum for stdin.
#
# Outputs:
#   Writes `sha512sum -`'s output to stdout.
# Returns:
#   1 if stdin is a TTY (no piped/redirected input).
sha512sum_gen_stdin() {
  debug "Starting ${FUNCNAME[0]}()"

  if [[ -t 0 ]]; then
    error "${ERROR_STDIN_NULL}"
    return 1
  fi

  cat | sha512sum -
}

# sha512sum_check_stdin()
#
# Checks a sha512sum-formatted checksum line read from stdin against the referenced file(s).
#
# Outputs:
#   Whatever `sha512sum --check` writes to stdout/stderr.
# Returns:
#   1 if stdin is a TTY; otherwise `sha512sum --check`'s exit status.
sha512sum_check_stdin() {
  debug "Starting ${FUNCNAME[0]}()"

  if [[ -t 0 ]]; then
    error "${ERROR_OPERAND_REQUIRED}"
    return 1
  fi

  local -ar sha512sum_check_options=(
    "--check"
    "--strict"
    "--warn"
  )
  debug "$(declare -p sha512sum_check_options)"

  sha512sum "${sha512sum_check_options[@]}" -
}

# sha512sum_gen()
#
# Generates a sha512 checksum for $1, or stdin when $1 is omitted.
#
# Arguments:
#   1) input - string (optional); data to hash. Read from stdin when omitted.
# Outputs:
#   Writes `sha512sum_gen_stdin`'s output to stdout.
# Returns:
#   1 if neither $1 nor piped/redirected stdin is provided.
sha512sum_gen() {
  debug "Starting ${FUNCNAME[0]}()"

  if (( $# )); then
    local -r input="$1"
  elif [[ ! -t 0 ]]; then
    local -r input="$(cat)"
  else
    error "${ERROR_STDIN_NULL} OR ${ERROR_OPERAND_REQUIRED}"
    return 1
  fi

  sha512sum_gen_stdin <<< "${input}"
}

# sha512sum_check()
#
# Checks a sha512sum-formatted checksum line, from $1 or stdin, against the referenced file(s).
#
# Arguments:
#   1) input - string (optional); a checksum line. Read from stdin when omitted.
# Outputs:
#   Whatever `sha512sum_check_stdin` writes to stdout/stderr.
# Returns:
#   1 if neither $1 nor piped/redirected stdin is provided.
sha512sum_check() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  if (( $# )); then
    local -r input="$1"
  elif [[ ! -t 0 ]]; then
    local -r input="$(cat)"
  else
    error "${ERROR_STDIN_NULL} OR ${ERROR_OPERAND_REQUIRED}"
    return 1
  fi

  sha512sum_check_stdin <<< "${input}"
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi
