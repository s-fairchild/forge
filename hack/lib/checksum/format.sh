# hack/lib/checksum/format.sh
#
# Parses and formats checksum values for use as Ignition merge-entry verification hashes.
# shellcheck shell=bash
# set -x

declare -r __hack_lib_checksum_format_sourced="true"

# checksum_parse_hash()
#
# Extracts the hash value (first whitespace-delimited field) from a checksum-tool line, e.g.
# "<hex>  -" from `sha512sum`'s output.
#
# Arguments:
#   1) input - string; a checksum-tool output line.
# Outputs:
#   Writes the parsed hash value to stdout.
# Returns:
#   1 if the parsed value is empty.
checksum_parse_hash() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r input="${1?$(error "${ERROR_OPERAND_REQUIRED}")}"

  local -r output="$(cut -d ' ' -f 1 <<< "${input}")"
  if [[ -z "${output}" ]]; then
    error "failed to parse checksum value. ${ERROR_STRING_EMPTY}"
    return 1
  fi

  printf "%s" "${output}"
}

# checksum_format_verification_hash_sha512()
#
# Formats a sha512 checksum-tool line (or a raw hex digest passed as $1) as an Ignition
# "sha512-<hex>" verification.hash value.
#
# Arguments:
#   1) input - string (optional); a raw checksum-tool output line/digest. When omitted, read
#      from stdin.
# Outputs:
#   Writes the "sha512-<hex>" formatted hash to stdout.
# Returns:
#   Non-zero if neither stdin nor $1 provided input.
checksum_format_verification_hash_sha512() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  if [[ ! -t 0 ]]; then
    local -r input="$(cat)"
  elif (( $# )); then
    local -r input="$1"
  else
    error "${ERROR_OPERAND_REQUIRED} OR ${ERROR_STDIN_NULL}"
  fi

  printf "sha512-%s" "$(checksum_parse_hash "${input}")"
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi

if [[ "${__bashkit_core_sourced:-}" != "true" ]]; then
  declare __bashkit_core="hack/vendor/bashkit/local/lib/bashkit/core/contract-utils.sh"
  [[ -f "${__bashkit_core}" ]] || fatal "${ERROR_FILE_NOT_FOUND}: ${__bashkit_core}"
  # shellcheck source=../../vendor/bashkit/local/lib/bashkit/core/contract-utils.sh
  . "${__bashkit_core}"
  unset __bashkit_core
fi
