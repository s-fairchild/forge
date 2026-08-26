# shellcheck shell=bash
# set -x

declare -r __hack_lib_checksum_format_sourced="true"

checksum_parse_hash() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r input="${1?$(error "$ERROR_OPERAND_REQUIRED")}"

    local -r output="$(cut -d ' ' -f 1 <<< "$input")"
    if [ -z "$output" ]; then
        error "failed to parse checksum value. $ERROR_STRING_EMPTY"
        return 1
    fi

    printf "%s" "$output"
}

checksum_format_verification_hash_sha512() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    if [ ! -t 0 ]; then
        local -r input="$(cat)"
    elif (( $# )); then
        local -r input="$1"
    else
        error "${ERROR_OPERAND_REQUIRED} OR ${ERROR_STDIN_NULL}"
    fi

    printf "sha512-%s" "$(checksum_parse_hash "$input")"
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi

if [ "${__vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="hack/vendor/bashkit/local/lib/bashkit/options-operands-utils.sh"
    [ -f "$__vendor_bashkit_local_lib_bashkit_options_operands_utils" ] || fatal "${ERROR_FILE_NOT_FOUND}: ${__vendor_bashkit_local_lib_bashkit_options_operands_utils}"
    # shellcheck source=../../vendor/bashkit/local/lib/bashkit/options-operands-utils.sh
    . "$__vendor_bashkit_local_lib_bashkit_options_operands_utils"
    unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi
