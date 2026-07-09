# shellcheck shell=bash

declare -r __hack_lib_checksum_sha512sum_sourced="true"

sha512sum() {
    command sha512sum
}

sha512sum_gen_stdin() {
    if [ -t 0 ]; then
        error "$ERROR_STDIN_NULL"
        return 1
    fi

    cat | sha512sum -
}

sha512sum_check_stdin() {
    if [ -t 0 ]; then
        error "$ERROR_ARG_REQUIRED"
        return 1
    fi

    local -ar sha512sum_check_options=(
        "--check"
        "--strict"
        --warn
    )
    debug "$(declare -p sha512sum_check_options)"

    # shellcheck disable=SC2068
    sha512sum ${sha512sum_check_options[@]} -
}

sha512sum_gen() {
    if (( $# )); then
        local -r input="$1"
    elif [ ! -t 0 ]; then
        local -r input="$(cat)"
    else
        error "$ERROR_STDIN_NULL and $ERROR_ARG_REQUIRED"
        return 1
    fi
    
    sha512sum_gen_stdin <<< "$input"
}

sha512sum_check() {
    if (( $# )); then
        local -r input="$1"
    elif [ ! -t 0 ]; then
        local -r input="$(cat)"
    else
        error "$ERROR_STDIN_NULL and $ERROR_ARG_REQUIRED"
        return 1
    fi

    sha512sum_check_stdin <<< "$input"
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
fi
