# shellcheck shell=bash
# set -x

declare -ri __hack_lib_checksum_format_sourced=1

checksum_parse_hash() {
    local -r input="${1?$(error "$ERROR_ARG_REQUIRED")}"

    local -r output="$(cut -d ' ' -f 1 <<< "$input")"
    if [ -z "$output" ]; then
        error "failed to parse checksum value. $ERROR_STRING_EMPTY"
        return 1
    fi

    printf "%s" "$output"
}

checksum_format_verification_hash_sha512() {
    if [ ! -t 0 ]; then
        local -r input="$(cat)"
    elif (( $# )); then
        local -r input="$1"
    else
        error "$ERROR_ARG_REQUIRED"
    fi

    printf "sha512-%s" "$(checksum_parse_hash "$input")"
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
fi
